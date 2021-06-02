// Licensed to the Software Freedom Conservancy (SFC) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The SFC licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package org.openqa.selenium.grid.distributor.local;

import com.google.common.collect.ImmutableSet;

import org.openqa.selenium.Beta;
import org.openqa.selenium.Capabilities;
import org.openqa.selenium.ImmutableCapabilities;
import org.openqa.selenium.RetrySessionRequestException;
import org.openqa.selenium.SessionNotCreatedException;
import org.openqa.selenium.WebDriverException;
import org.openqa.selenium.concurrent.Regularly;
import org.openqa.selenium.events.EventBus;
import org.openqa.selenium.grid.config.Config;
import org.openqa.selenium.grid.data.CreateSessionRequest;
import org.openqa.selenium.grid.data.CreateSessionResponse;
import org.openqa.selenium.grid.data.DistributorStatus;
import org.openqa.selenium.grid.data.NewSessionRequestEvent;
import org.openqa.selenium.grid.data.NodeAddedEvent;
import org.openqa.selenium.grid.data.NodeDrainComplete;
import org.openqa.selenium.grid.data.NodeHeartBeatEvent;
import org.openqa.selenium.grid.data.NodeId;
import org.openqa.selenium.grid.data.NodeStatus;
import org.openqa.selenium.grid.data.NodeStatusEvent;
import org.openqa.selenium.grid.data.RequestId;
import org.openqa.selenium.grid.data.SessionRequest;
import org.openqa.selenium.grid.data.SessionRequestCapability;
import org.openqa.selenium.grid.data.Slot;
import org.openqa.selenium.grid.data.SlotId;
import org.openqa.selenium.grid.data.TraceSessionRequest;
import org.openqa.selenium.grid.distributor.Distributor;
import org.openqa.selenium.grid.distributor.config.DistributorOptions;
import org.openqa.selenium.grid.distributor.selector.SlotSelector;
import org.openqa.selenium.grid.log.LoggingOptions;
import org.openqa.selenium.grid.node.HealthCheck;
import org.openqa.selenium.grid.node.Node;
import org.openqa.selenium.grid.node.remote.RemoteNode;
import org.openqa.selenium.grid.security.Secret;
import org.openqa.selenium.grid.security.SecretOptions;
import org.openqa.selenium.grid.server.EventBusOptions;
import org.openqa.selenium.grid.server.NetworkOptions;
import org.openqa.selenium.grid.sessionmap.SessionMap;
import org.openqa.selenium.grid.sessionmap.config.SessionMapOptions;
import org.openqa.selenium.grid.sessionqueue.NewSessionQueue;
import org.openqa.selenium.grid.sessionqueue.config.NewSessionQueueOptions;
import org.openqa.selenium.internal.Either;
import org.openqa.selenium.internal.Require;
import org.openqa.selenium.remote.SessionId;
import org.openqa.selenium.remote.http.HttpClient;
import org.openqa.selenium.remote.tracing.AttributeKey;
import org.openqa.selenium.remote.tracing.EventAttribute;
import org.openqa.selenium.remote.tracing.EventAttributeValue;
import org.openqa.selenium.remote.tracing.Span;
import org.openqa.selenium.remote.tracing.Status;
import org.openqa.selenium.remote.tracing.Tracer;
import org.openqa.selenium.status.HasReadyState;

import java.io.UncheckedIOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.stream.Collectors;

import static com.google.common.collect.ImmutableSet.toImmutableSet;
import static org.openqa.selenium.grid.data.Availability.DOWN;
import static org.openqa.selenium.grid.data.Availability.DRAINING;
import static org.openqa.selenium.internal.Debug.getDebugLogLevel;
import static org.openqa.selenium.remote.RemoteTags.CAPABILITIES;
import static org.openqa.selenium.remote.RemoteTags.CAPABILITIES_EVENT;
import static org.openqa.selenium.remote.RemoteTags.SESSION_ID;
import static org.openqa.selenium.remote.RemoteTags.SESSION_ID_EVENT;
import static org.openqa.selenium.remote.tracing.AttributeKey.SESSION_URI;
import static org.openqa.selenium.remote.tracing.Tags.EXCEPTION;

public class LocalDistributor extends Distributor {

  private static final Logger LOG = Logger.getLogger(LocalDistributor.class.getName());

  private final Tracer tracer;
  private final EventBus bus;
  private final HttpClient.Factory clientFactory;
  private final SessionMap sessions;
  private final SlotSelector slotSelector;
  private final Secret registrationSecret;
  private final Regularly hostChecker = new Regularly("distributor host checker");
  private final Map<NodeId, Runnable> allChecks = new HashMap<>();
  private final Duration healthcheckInterval;

  private final ReadWriteLock lock = new ReentrantReadWriteLock(/* fair */ true);
  private final GridModel model;
  private final Map<NodeId, Node> nodes;

  private final NewSessionQueue sessionQueue;
  private final Regularly regularly;

  private final boolean rejectUnsupportedCaps;

  public LocalDistributor(
    Tracer tracer,
    EventBus bus,
    HttpClient.Factory clientFactory,
    SessionMap sessions,
    NewSessionQueue sessionQueue,
    SlotSelector slotSelector,
    Secret registrationSecret,
    Duration healthcheckInterval,
    boolean rejectUnsupportedCaps) {
    super(tracer, clientFactory, registrationSecret);
    this.tracer = Require.nonNull("Tracer", tracer);
    this.bus = Require.nonNull("Event bus", bus);
    this.clientFactory = Require.nonNull("HTTP client factory", clientFactory);
    this.sessions = Require.nonNull("Session map", sessions);
    this.sessionQueue = Require.nonNull("New Session Request Queue", sessionQueue);
    this.slotSelector = Require.nonNull("Slot selector", slotSelector);
    this.registrationSecret = Require.nonNull("Registration secret", registrationSecret);
    this.healthcheckInterval = Require.nonNull("Health check interval", healthcheckInterval);
    this.model = new GridModel(bus);
    this.nodes = new ConcurrentHashMap<>();
    this.rejectUnsupportedCaps = rejectUnsupportedCaps;

    bus.addListener(NodeStatusEvent.listener(this::register));
    bus.addListener(NodeStatusEvent.listener(model::refresh));
    bus.addListener(NodeHeartBeatEvent.listener(nodeStatus -> {
      if (nodes.containsKey(nodeStatus.getId())) {
        model.touch(nodeStatus.getId());
      } else {
        register(nodeStatus);
      }
    }));

    regularly = new Regularly(
      Executors.newSingleThreadScheduledExecutor(
        r -> {
          Thread thread = new Thread(r);
          thread.setName("New Session Queue");
          thread.setDaemon(true);
          return thread;
        }));

    NewSessionRunnable newSessionRunnable = new NewSessionRunnable();
    bus.addListener(NodeDrainComplete.listener(this::remove));
    bus.addListener(NewSessionRequestEvent.listener(ignored -> newSessionRunnable.run()));

    regularly.submit(model::purgeDeadNodes, Duration.ofSeconds(30), Duration.ofSeconds(30));
    regularly.submit(newSessionRunnable, Duration.ofSeconds(5), Duration.ofSeconds(5));
  }

  public static Distributor create(Config config) {
    Tracer tracer = new LoggingOptions(config).getTracer();
    EventBus bus = new EventBusOptions(config).getEventBus();
    DistributorOptions distributorOptions = new DistributorOptions(config);
    HttpClient.Factory clientFactory = new NetworkOptions(config).getHttpClientFactory(tracer);
    SessionMap sessions = new SessionMapOptions(config).getSessionMap();
    SecretOptions secretOptions = new SecretOptions(config);
    NewSessionQueue sessionQueue = new NewSessionQueueOptions(config).getSessionQueue(
      "org.openqa.selenium.grid.sessionqueue.remote.RemoteNewSessionQueue");
    return new LocalDistributor(
      tracer,
      bus,
      clientFactory,
      sessions,
      sessionQueue,
      distributorOptions.getSlotSelector(),
      secretOptions.getRegistrationSecret(),
      distributorOptions.getHealthCheckInterval(),
      distributorOptions.shouldRejectUnsupportedCaps());
  }

  @Override
  public boolean isReady() {
    try {
      return ImmutableSet.of(bus, sessions).parallelStream()
        .map(HasReadyState::isReady)
        .reduce(true, Boolean::logicalAnd);
    } catch (RuntimeException e) {
      return false;
    }
  }

  private void register(NodeStatus status) {
    Require.nonNull("Node", status);

    Lock writeLock = lock.writeLock();
    writeLock.lock();
    try {
      if (nodes.containsKey(status.getId())) {
        return;
      }

      Set<Capabilities> capabilities = status.getSlots().stream()
        .map(Slot::getStereotype)
        .map(ImmutableCapabilities::copyOf)
        .collect(toImmutableSet());

      // A new node! Add this as a remote node, since we've not called add
      RemoteNode remoteNode = new RemoteNode(
        tracer,
        clientFactory,
        status.getId(),
        status.getUri(),
        registrationSecret,
        capabilities);

      add(remoteNode);
    } finally {
      writeLock.unlock();
    }
  }

  @Override
  public LocalDistributor add(Node node) {
    Require.nonNull("Node", node);

    LOG.info(String.format("Added node %s at %s.", node.getId(), node.getUri()));

    nodes.put(node.getId(), node);
    model.add(node.getStatus());

    // Extract the health check
    Runnable runnableHealthCheck = asRunnableHealthCheck(node);
    allChecks.put(node.getId(), runnableHealthCheck);
    hostChecker.submit(runnableHealthCheck, healthcheckInterval, Duration.ofSeconds(30));

    bus.fire(new NodeAddedEvent(node.getId()));

    return this;
  }

  private Runnable asRunnableHealthCheck(Node node) {
    HealthCheck healthCheck = node.getHealthCheck();
    NodeId id = node.getId();
    return () -> {
      HealthCheck.Result result;
      try {
        result = healthCheck.check();
      } catch (Exception e) {
        LOG.log(Level.WARNING, "Unable to process node " + id, e);
        result = new HealthCheck.Result(DOWN, "Unable to run healthcheck. Assuming down");
      }

      Lock writeLock = lock.writeLock();
      writeLock.lock();
      try {
        model.setAvailability(id, result.getAvailability());
      } finally {
        writeLock.unlock();
      }
    };
  }

  @Override
  public boolean drain(NodeId nodeId) {
    Node node = nodes.get(nodeId);
    if (node == null) {
      LOG.info("Asked to drain unregistered node " + nodeId);
      return false;
    }

    Lock writeLock = lock.writeLock();
    writeLock.lock();
    try {
      node.drain();
      model.setAvailability(nodeId, DRAINING);
    } finally {
      writeLock.unlock();
    }

    return node.isDraining();
  }

  public void remove(NodeId nodeId) {
    Lock writeLock = lock.writeLock();
    writeLock.lock();
    try {
      model.remove(nodeId);
      Runnable runnable = allChecks.remove(nodeId);
      if (runnable != null) {
        hostChecker.remove(runnable);
      }
    } finally {
      writeLock.unlock();
    }
  }

  @Override
  public DistributorStatus getStatus() {
    Lock readLock = this.lock.readLock();
    readLock.lock();
    try {
      return new DistributorStatus(model.getSnapshot());
    } finally {
      readLock.unlock();
    }
  }

  @Beta
  public void refresh() {
    List<Runnable> allHealthChecks = new ArrayList<>();

    Lock readLock = this.lock.readLock();
    readLock.lock();
    try {
      allHealthChecks.addAll(allChecks.values());
    } finally {
      readLock.unlock();
    }

    allHealthChecks.parallelStream().forEach(Runnable::run);
  }

  protected Set<NodeStatus> getAvailableNodes() {
    Lock readLock = this.lock.readLock();
    readLock.lock();
    try {
      return model.getSnapshot().stream()
        .filter(node -> !DOWN.equals(node.getAvailability()))
        .collect(toImmutableSet());
    } finally {
      readLock.unlock();
    }
  }

  @Override
  public Either<SessionNotCreatedException, CreateSessionResponse> newSession(SessionRequest request)
    throws SessionNotCreatedException {
    Require.nonNull("Requests to process", request);

    Span span = tracer.getCurrentContext().createSpan("distributor.new_session");
    Map<String, EventAttributeValue> attributeMap = new HashMap<>();
    try {
      attributeMap.put(AttributeKey.LOGGER_CLASS.getKey(),
        EventAttribute.setValue(getClass().getName()));

      attributeMap.put("request.payload", EventAttribute.setValue(request.getDesiredCapabilities().toString()));
      String sessionReceivedMessage = "Session request received by the distributor";
      span.addEvent(sessionReceivedMessage, attributeMap);
      LOG.info(String.format("%s: \n %s", sessionReceivedMessage, request.getDesiredCapabilities()));

      // If there are no capabilities at all, something is horribly wrong
      if (request.getDesiredCapabilities().isEmpty()) {
        SessionNotCreatedException exception =
          new SessionNotCreatedException("No capabilities found in session request payload");
        EXCEPTION.accept(attributeMap, exception);
        attributeMap.put(AttributeKey.EXCEPTION_MESSAGE.getKey(),
          EventAttribute.setValue("Unable to create session. No capabilities found: " +
            exception.getMessage()));
        span.addEvent(AttributeKey.EXCEPTION_EVENT.getKey(), attributeMap);
        return Either.left(exception);
      }

      boolean retry = false;
      SessionNotCreatedException lastFailure = new SessionNotCreatedException("Unable to create new session");
      for (Capabilities caps : request.getDesiredCapabilities()) {
        if (!isSupported(caps)) {
          continue;
        }

        // Try and find a slot that we can use for this session. While we
        // are finding the slot, no other session can possibly be started.
        // Therefore, spend as little time as possible holding the write
        // lock, and release it as quickly as possible. Under no
        // circumstances should we try to actually start the session itself
        // in this next block of code.
        SlotId selectedSlot = reserveSlot(request.getRequestId(), caps);
        if (selectedSlot == null) {
          LOG.info(String.format("Unable to find slot for request %s. May retry: %s ", request.getRequestId(), caps));
          retry = true;
          continue;
        }

        CreateSessionRequest singleRequest = new CreateSessionRequest(
          request.getDownstreamDialects(),
          caps,
          request.getMetadata());

        try {
          CreateSessionResponse response = startSession(selectedSlot, singleRequest);
          sessions.add(response.getSession());
          model.setSession(selectedSlot, response.getSession());

          SessionId sessionId = response.getSession().getId();
          Capabilities sessionCaps = response.getSession().getCapabilities();
          String sessionUri = response.getSession().getUri().toString();
          SESSION_ID.accept(span, sessionId);
          CAPABILITIES.accept(span, sessionCaps);
          SESSION_ID_EVENT.accept(attributeMap, sessionId);
          CAPABILITIES_EVENT.accept(attributeMap, sessionCaps);
          span.setAttribute(SESSION_URI.getKey(), sessionUri);
          attributeMap.put(SESSION_URI.getKey(), EventAttribute.setValue(sessionUri));

          String sessionCreatedMessage = "Session created by the distributor";
          span.addEvent(sessionCreatedMessage, attributeMap);
          LOG.info(String.format("%s. Id: %s, Caps: %s", sessionCreatedMessage, sessionId, sessionCaps));

          return Either.right(response);
        } catch (SessionNotCreatedException e) {
          model.setSession(selectedSlot, null);
          lastFailure = e;
        }
      }

      // If we've made it this far, we've not been able to start a session
      if (retry) {
        lastFailure = new RetrySessionRequestException(
          "Will re-attempt to find a node which can run this session",
          lastFailure);
        attributeMap.put(
          AttributeKey.EXCEPTION_MESSAGE.getKey(),
          EventAttribute.setValue("Will retry session " + request.getRequestId()));
      } else {
        EXCEPTION.accept(attributeMap, lastFailure);
        attributeMap.put(AttributeKey.EXCEPTION_MESSAGE.getKey(),
          EventAttribute.setValue("Unable to create session: " + lastFailure.getMessage()));
        span.addEvent(AttributeKey.EXCEPTION_EVENT.getKey(), attributeMap);
      }
      return Either.left(lastFailure);
    } catch (SessionNotCreatedException e) {
      span.setAttribute(AttributeKey.ERROR.getKey(), true);
      span.setStatus(Status.ABORTED);

      EXCEPTION.accept(attributeMap, e);
      attributeMap.put(AttributeKey.EXCEPTION_MESSAGE.getKey(),
        EventAttribute.setValue("Unable to create session: " + e.getMessage()));
      span.addEvent(AttributeKey.EXCEPTION_EVENT.getKey(), attributeMap);

      return Either.left(e);
    } catch (UncheckedIOException e) {
      span.setAttribute(AttributeKey.ERROR.getKey(), true);
      span.setStatus(Status.UNKNOWN);

      EXCEPTION.accept(attributeMap, e);
      attributeMap.put(AttributeKey.EXCEPTION_MESSAGE.getKey(),
        EventAttribute.setValue("Unknown error in LocalDistributor while creating session: " + e.getMessage()));
      span.addEvent(AttributeKey.EXCEPTION_EVENT.getKey(), attributeMap);

      return Either.left(new SessionNotCreatedException(e.getMessage(), e));
    } finally {
      span.close();
    }
  }

  private CreateSessionResponse startSession(SlotId selectedSlot, CreateSessionRequest singleRequest) {
    Node node = nodes.get(selectedSlot.getOwningNodeId());
    if (node == null) {
      throw new SessionNotCreatedException("Unable to find owning node for slot");
    }

    Either<WebDriverException, CreateSessionResponse> result;
    try {
      result = node.newSession(singleRequest);
    } catch (SessionNotCreatedException e) {
      result = Either.left(e);
    } catch (RuntimeException e) {
      result = Either.left(new SessionNotCreatedException(e.getMessage(), e));
    }
    if (result.isLeft()) {
      WebDriverException exception = result.left();
      if (exception instanceof SessionNotCreatedException) {
        throw exception;
      }
      throw new SessionNotCreatedException(exception.getMessage(), exception);
    }

    return result.right();
  }

  private SlotId reserveSlot(RequestId requestId, Capabilities caps) {
    Lock writeLock = lock.writeLock();
    writeLock.lock();
    try {
      Set<SlotId> slotIds = slotSelector.selectSlot(caps, getAvailableNodes());
      if (slotIds.isEmpty()) {
        LOG.log(
          getDebugLogLevel(),
          String.format("No slots found for request %s and capabilities %s", requestId, caps));
        return null;
      }

      for (SlotId slotId : slotIds) {
        if (reserve(slotId)) {
          return slotId;
        }
      }

      return null;
    } finally {
      writeLock.unlock();
    }
  }

  private boolean isSupported(Capabilities caps) {
    return getAvailableNodes().stream().anyMatch(node -> node.hasCapability(caps));
  }

  private boolean reserve(SlotId id) {
    Require.nonNull("Slot ID", id);

    Lock writeLock = this.lock.writeLock();
    writeLock.lock();
    try {
      Node node = nodes.get(id.getOwningNodeId());
      if (node == null) {
        LOG.log(getDebugLogLevel(), String.format("Unable to find node with id %s", id));
        return false;
      }

      return model.reserve(id);
    } finally {
      writeLock.unlock();
    }
  }

  public void callExecutorShutdown() {
    LOG.info("Shutting down Distributor executor service");
    regularly.shutdown();
  }

  public class NewSessionRunnable implements Runnable {

    @Override
    public void run() {
      if (rejectUnsupportedCaps) {
        checkMatchingSlot(sessionQueue.getQueueContents());
      }
      int initialSize = sessionQueue.getQueueContents().size();
      boolean retry = initialSize != 0;

      while (retry) {
        // We deliberately run this outside of a lock: if we're unsuccessful
        // starting the session, we just put the request back on the queue.
        // This does mean, however, that under high contention, we might end
        // up starving a session request.
        Set<Capabilities> stereotypes =
            getAvailableNodes().stream()
                .filter(NodeStatus::hasCapacity)
                .map(
                    node ->
                        node.getSlots().stream()
                            .map(Slot::getStereotype)
                            .collect(Collectors.toSet()))
                .flatMap(Collection::stream)
                .collect(Collectors.toSet());

        Optional<SessionRequest> maybeRequest = sessionQueue.getNextAvailable(stereotypes);
        maybeRequest.ifPresent(this::handleNewSessionRequest);

        int currentSize = sessionQueue.getQueueContents().size();
        retry = currentSize != 0 && currentSize != initialSize;
        initialSize = currentSize;
      }
    }

    private void checkMatchingSlot(List<SessionRequestCapability> sessionRequests) {
      for(SessionRequestCapability request : sessionRequests) {
        long unmatchableCount = request.getDesiredCapabilities().stream()
          .filter(caps -> !isSupported(caps))
          .count();

        if (unmatchableCount == request.getDesiredCapabilities().size()) {
          SessionNotCreatedException exception = new SessionNotCreatedException(
            "No nodes support the capabilities in the request");
          sessionQueue.complete(request.getRequestId(), Either.left(exception));
        }
      }
    }

    private void handleNewSessionRequest(SessionRequest sessionRequest) {
      RequestId reqId = sessionRequest.getRequestId();

      try (Span span = TraceSessionRequest.extract(tracer, sessionRequest).createSpan("distributor.poll_queue")) {
        Map<String, EventAttributeValue> attributeMap = new HashMap<>();
        attributeMap.put(
          AttributeKey.LOGGER_CLASS.getKey(),
          EventAttribute.setValue(getClass().getName()));
        span.setAttribute(AttributeKey.REQUEST_ID.getKey(), reqId.toString());
        attributeMap.put(
          AttributeKey.REQUEST_ID.getKey(),
          EventAttribute.setValue(reqId.toString()));

        attributeMap.put("request", EventAttribute.setValue(sessionRequest.toString()));
        Either<SessionNotCreatedException, CreateSessionResponse> response = newSession(sessionRequest);

        if (response.isLeft() && response.left() instanceof RetrySessionRequestException) {
          try(Span childSpan = span.createSpan("distributor.retry")) {
            LOG.info("Retrying");
            boolean retried = sessionQueue.retryAddToQueue(sessionRequest);

            attributeMap.put("request.retry_add", EventAttribute.setValue(retried));
            childSpan.addEvent("Retry adding to front of queue. No slot available.", attributeMap);

            if (retried) {
              return;
            }
            childSpan.addEvent("retrying_request", attributeMap);
          }
        }

        sessionQueue.complete(reqId, response);
      }
    }
  }
}
