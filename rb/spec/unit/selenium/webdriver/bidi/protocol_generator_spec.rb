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

require File.expand_path('../spec_helper', __dir__)
require File.expand_path('../../../../../lib/selenium/webdriver/bidi/support/bidi-generate', __dir__)

module BiDiGenerate
  describe '.camel_to_snake' do
    it 'splits camelCase on word boundaries' do
      expect(BiDiGenerate.camel_to_snake('browsingContext')).to eq('browsing_context')
    end

    it 'keeps acronym runs together' do
      expect(BiDiGenerate.camel_to_snake('setBypassCSP')).to eq('set_bypass_csp')
    end
  end

  describe '.enum_key' do
    it 'maps a leading minus to neg_' do
      expect(BiDiGenerate.enum_key('-Infinity')).to eq('neg_infinity')
    end

    it 'collapses punctuation' do
      expect(BiDiGenerate.enum_key('dedicated-worker')).to eq('dedicated_worker')
    end
  end

  describe Coverage do
    # A miniature schema exercising one type of every category the classifier
    # recognizes, so the category tally is asserted exhaustively.
    let(:schema) do
      {
        'types' => {
          'log.Level' => {'kind' => 'enum', 'values' => %w[debug info]},
          'network.UrlPattern' => {'kind' => 'union', 'variants' => %w[network.UrlPatternString]},
          'network.UrlPatternString' => {
            'kind' => 'record',
            'fields' => [
              {'name' => 'type', 'wire' => 'type', 'required' => true, 'type' => {'const' => 'string'}},
              {'name' => 'pattern', 'wire' => 'pattern', 'required' => true, 'type' => {'primitive' => 'string'}}
            ]
          },
          'script.LocalValue' => {'kind' => 'alias', 'type' => {'union' => [{'ref' => 'network.UrlPattern'}]}},
          'session.EndResult' => {'kind' => 'alias', 'type' => {'ref' => 'network.UrlPatternString'}},
          'js-uint' => {'kind' => 'alias', 'type' => {'primitive' => 'unknown'}},
          'session.Capabilities' => {
            'kind' => 'record',
            'fields' => [{'name' => 'pattern', 'wire' => 'pattern', 'required' => false,
                          'type' => {'ref' => 'network.UrlPattern'}}]
          },
          'session.CapabilityRequest' => {'kind' => 'record', 'extensible' => true, 'fields' => []},
          'script.NodeAttributes' => {'kind' => 'record', 'fields' => [], 'map' => {'primitive' => 'string'}}
        },
        'commands' => [],
        'events' => []
      }
    end

    it 'classifies every type into exactly one category, accounting for all of them' do
      report = described_class.new(schema).check!

      expect(report.total).to eq(schema['types'].size)
      expect(report.categories.values.sum).to eq(report.total)
      expect(report.categories).to eq(
        enum: 1,
        union: 1,
        scalar_record: 1,
        union_alias: 1,
        ref_alias: 1,
        scalar_alias: 1,
        nested_record: 1,
        extensible_record: 1,
        map_record: 1
      )
    end

    it 'raises on an unrecognized type kind' do
      schema['types']['bad'] = {'kind' => 'tuple', 'items' => []}
      expect { described_class.new(schema).check! }.to raise_error(Coverage::Unrecognized, /tuple/)
    end

    it 'raises on an unrecognized type node shape' do
      schema['types']['session.Capabilities']['fields'][0]['type'] = {'tuple' => []}
      expect { described_class.new(schema).check! }.to raise_error(Coverage::Unrecognized, /tuple/)
    end

    it 'raises on a dangling reference' do
      schema['types']['session.EndResult']['type'] = {'ref' => 'does.NotExist'}
      expect { described_class.new(schema).check! }.to raise_error(Coverage::Unrecognized, /does\.NotExist/)
    end
  end
end
