#!/usr/bin/env bash

# rake runs on the Bazel-managed Ruby and bundle, so no local Ruby or Java is needed
bazel build --noshow_progress --show_result=0 --ui_event_filters=-info //:rake || exit $?

# This code supports both:
# ./go "namespace:task[--arg1,--arg2]" --rake-flag
# ./go namespace:task --arg1 --arg2 -- --rake-flag

# The first argument is always the Rake task name
task="$1"
shift

# Initialize arrays for rake flags and task arguments
rake_flags=()
task_args=()

# Arguments before -- are task arguments
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    break
  fi
  task_args+=("$1")
  shift
done

# Remaining arguments are rake flags
rake_flags=("$@")

# If we have task args, format them
if [ ${#task_args[@]} -gt 0 ]; then
  # Convert task args array to comma-separated string
  args=$(IFS=','; echo "${task_args[*]}")
  task="$task[$args]"
  echo "Executing rake task: $task"
fi


# Windows reaches this script through bash too (CI and the go.bat shim), where the launcher is a .cmd
launcher=bazel-bin/rake.sh
[ -f bazel-bin/rake.cmd ] && launcher=bazel-bin/rake.cmd
exec "$launcher" $task "${rake_flags[@]}"
