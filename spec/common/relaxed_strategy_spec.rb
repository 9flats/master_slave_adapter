$: << File.expand_path(File.join(File.dirname( __FILE__ ), '..', '..', 'lib'))

require 'rspec'
require 'common/support/connection_setup_helper'
require 'common/support/strategies/default'
require 'common/support/master_slave_adapter_examples'
require 'active_record/connection_adapters/master_slave_adapter/lag_strategies/relaxed_strategy'
require 'active_record/connection_adapters/master_slave_adapter/clocks/default_clock'
require 'active_record/connection_adapters/master_slave_adapter/clocks/heartbeat_clock'

module ActiveRecord
  class Base
    cattr_accessor :master_mock, :slave_mock

    def self.test_connection(config)
      config[:database] == 'slave' ? slave_mock : master_mock
    end

    def self.test_master_slave_connection(config)
      ConnectionAdapters::TestMasterSlaveAdapter.new(config, logger)
    end
  end

  module ConnectionAdapters
    class TestMasterSlaveAdapter < AbstractAdapter
      include MasterSlaveAdapter

      def slave_consistent(*args)
        true
      end

      def slave_inconsistent(*args)
        false
      end

      def master_clock
      end

      def slave_clock(connection)
      end

      def connection_error?(exception)
      end
    end
  end
end

describe ActiveRecord::ConnectionAdapters::MasterSlaveAdapter do
  context 'using RelaxedStrategy' do
    context "with consistency" do
      before do
        class ActiveRecord::ConnectionAdapters::TestMasterSlaveAdapter
          alias :slave_consistent? :slave_consistent
        end
      end

      let(:connection_adapter) { 'test' }
      let(:clock_implementation) { 'DefaultClock' }
      let(:lag_strategy) { 'RelaxedStrategy' }
      include_context 'connection setup'

      it_should_behave_like 'master_slave_adapter'
      it_should_behave_like 'DefaultStrategy'

      describe 'connection stack' do
        it "should start with the slave connection on top" do
          expect do
            adapter_connection.current_connection.should == slave_connection
          end
        end

        it "should use the slave connection" do
          master_connection.should_receive(:execute).with("INSERT 42").exactly(1).times
          slave_connection.should_not_receive(:execute).with("INSERT 42")

          ActiveRecord::Base.with_slave do
            adapter_connection.current_connection.should == slave_connection
            ActiveRecord::Base.with_master do
              adapter_connection.current_connection.should == master_connection
              ActiveRecord::Base.with_slave do
                adapter_connection.current_connection.should == slave_connection
                adapter_connection.execute("INSERT 42")
                adapter_connection.current_connection.should == slave_connection
              end
              adapter_connection.current_connection.should == slave_connection
            end
            adapter_connection.current_connection.should == slave_connection
          end
          adapter_connection.current_connection.should == slave_connection
        end
      end

    end

    context 'without consistency' do
      before do
        class ActiveRecord::ConnectionAdapters::TestMasterSlaveAdapter
          alias :slave_consistent? :slave_inconsistent
        end
      end
      let(:connection_adapter) { 'test' }
      let(:clock_implementation) { 'DefaultClock' }
      let(:lag_strategy) { 'RelaxedStrategy' }
      include_context 'connection setup'

      describe 'select behavior' do
        SelectMethods.each do |method|
          it "should send the method '#{method}' to the slave connection" do
            master_connection.stub!( :open_transactions ).and_return( 0 )
            master_connection.should_receive( method ).with('testing').and_return( true )
            adapter_connection.send( method, 'testing' )
          end

          it "should send the method '#{method}' to the master connection when slave is inconsistent" do
            master_connection.should_receive( method ).with('testing').and_return( true )
            ActiveRecord::Base.with_slave do
              adapter_connection.send( method, 'testing' )
            end
          end

          context 'given slave is not available' do
            it 'queries the master' do
              slave_connection.stub(:connection_error?).and_return(true)
              master_connection.should_receive(method).with('testing').and_return( true )

              ActiveRecord::Base.with_slave do
                adapter_connection.send(method, 'testing')
              end
            end
          end
        end # /SelectMethods.each
      end

      describe "query cache" do
        describe "#cache" do
          it "activities query caching on all connections" do
            master_connection.should_receive(:cache).and_yield
            slave_connection.should_receive(:cache).and_yield
            slave_connection.should_not_receive(:select_value)
            master_connection.should_receive(:select_value)

            adapter_connection.cache do
              adapter_connection.select_value("SELECT 42")
            end
          end
        end

        describe "#uncached" do
          it "deactivates query caching on all connections" do
            master_connection.should_receive(:uncached).and_yield
            slave_connection.should_receive(:uncached).and_yield
            slave_connection.should_not_receive(:select_value)
            master_connection.should_receive(:select_value)

            adapter_connection.uncached do
              adapter_connection.select_value("SELECT 42")
            end
          end
        end
      end

      describe "connection stack" do
        it "should start with the master connection on top" do
          adapter_connection.current_connection.should == master_connection
        end

        it "should only use the master connection" do
          master_connection.should_receive(:execute).with("INSERT 42").exactly(1).times
          slave_connection.should_not_receive(:execute).with("INSERT 42")

          ActiveRecord::Base.with_slave do
            adapter_connection.current_connection.should == master_connection
            ActiveRecord::Base.with_master do
              adapter_connection.current_connection.should == master_connection
              ActiveRecord::Base.with_slave do
                adapter_connection.current_connection.should == master_connection
                adapter_connection.execute("INSERT 42")
                adapter_connection.current_connection.should == master_connection
              end
              adapter_connection.current_connection.should == master_connection
            end
            adapter_connection.current_connection.should == master_connection
          end
          adapter_connection.current_connection.should == master_connection
        end
      end
    end
  end
end
