# frozen_string_literal: true

# Licensed to the Software Freedom Conservancy (SFC) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The SFC licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Loads the generated BiDi protocol layer: the hand-written serialization runtime
# first (it defines the {BiDi::Data}/{BiDi::Union} bases the generated classes
# resolve by lexical scope), then every generated domain module. Cross-domain
# references are lazy (resolved via +Protocol.const_get+ at call time), so the
# domain files load in any order. Full autoload wiring is deferred (Phase 6).
require 'selenium/webdriver/bidi/serialization'
Dir.glob(File.join(__dir__, 'protocol', '*.rb')).sort.each { |file| require file }
