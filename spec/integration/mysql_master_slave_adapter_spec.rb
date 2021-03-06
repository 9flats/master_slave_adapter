$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'rspec'
require 'master_slave_adapter'
require 'integration/support/shared_mysql_examples'

describe "ActiveRecord::ConnectionAdapters::MysqlMasterSlaveAdapter" do
  let(:connection_adapter) { 'mysql' }

  it_should_behave_like "a MySQL MasterSlaveAdapter"
end
