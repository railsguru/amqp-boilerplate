require 'spec_helper'

# NOTE See spec_helper for Consumer definitions
describe AMQP::Boilerplate::Consumer do
  before(:each) do
    AMQP::Boilerplate.stub(:logger).and_return(mock.as_null_object)
    @channel = mock(AMQP::Channel)
    @channel.stub(:on_error).and_return(true)
  end

  describe "#handle_channel_error" do
    before(:each) do
      @channel_close = mock(:reply_code => "OK", :reply_text => "Something")
    end

    it "should log the code and message" do
      AMQP::Boilerplate.logger.should_receive(:error).with("[BarConsumer#handle_channel_error] Code = #{@channel_close.reply_code}, message = #{@channel_close.reply_text}")

      BarConsumer.new.handle_channel_error(@channel, @channel_close)
    end
  end

  describe "#handle_message" do
    it "should raise an error (must be implemented by subclasses)" do
      expect {
        AMQP::Boilerplate::Consumer.new.handle_message(anything, anything)
      }.to raise_error(NotImplementedError, "The time has come to implement your own consumer class. Good luck!")
    end
  end

  describe ".amqp_queue" do
    before(:each) do
      AMQP.stub(:channel).and_return(@channel)
      @queue = mock(AMQP::Queue)
      @channel.stub(:queue).and_return(@queue)
      @queue.stub(:subscribe)
    end

    it "should use a default name for queue" do
      @channel.should_receive(:queue).with(AMQ::Protocol::EMPTY_STRING, anything).and_return(@queue)

      FooConsumer.start
    end

    it "should use a empty hash for queue options" do
      @channel.should_receive(:queue).with(anything, {}).and_return(@queue)

      FooConsumer.start
    end
  end

  describe ".start" do
    before(:each) do
      @consumer = BarConsumer.new
      BarConsumer.stub(:new).and_return(@consumer)

      AMQP.stub(:channel).and_return(@channel)

      @queue = mock(AMQP::Queue)
      @channel.stub(:queue).and_return(@queue)
      @queue.stub(:subscribe)
    end

    it "should use a channel" do
      AMQP.should_receive(:channel).and_return(@channel)
      BarConsumer.start
    end

    it "should instantiate a consumer" do
      BarConsumer.should_receive(:new).and_return(@consumer)
      BarConsumer.start
    end

    it "should register a channel error handler" do
      @channel.should_receive(:on_error)
      BarConsumer.start
    end

    it "should instantiate a queue with the proper queue name" do
      @channel.should_receive(:queue).with("queue.name.here", anything)
      BarConsumer.start
    end

    it "should instantiate a queue provided with options" do
      @channel.should_receive(:queue).with(anything, :durable => true)
      BarConsumer.start
    end

    it "should subscribe to the queue" do
      @queue.should_receive(:subscribe).with(:ack => true)
      BarConsumer.start
    end

    describe "when an exchange name has been provided" do
      before(:each) do
        @exchange_name = "amq.fanout"
      end

      after(:each) do
        BarConsumer.amqp_exchange(nil)
      end

      it "should bind to the exchange" do
        BarConsumer.amqp_exchange(@exchange_name)
        @queue.should_receive(:bind).with(@exchange_name, anything)
        BarConsumer.start
      end

      it "should pass an empty hash when no amqp_exchange options are defined" do
        BarConsumer.amqp_exchange(@exchange_name)
        @queue.should_receive(:bind).with(anything, {})
        BarConsumer.start
      end

      it "should pass options to the bind method" do
        BarConsumer.amqp_exchange(@exchange_name, :routing_key => 'foo.bar')
        @queue.should_receive(:bind).with(anything, :routing_key => 'foo.bar')
        BarConsumer.start
      end
    end

    describe "when no exchange name provided" do
      before(:each) do
        BarConsumer.amqp_exchange(nil)
      end

      it "should not explicitly bind to an exchange" do
        @queue.should_not_receive(:bind)
        BarConsumer.start
      end
    end
  end

  describe "#handle_message_wrapper" do
    before(:each) do
      @consumer = BarConsumer.new

      @metadata = mock("metadata")
      @payload = "payload"
    end

    it "should let handle_message do the heavy lifting" do
      @consumer.should_receive(:handle_message).with(@metadata, @payload)
      @consumer.handle_message_wrapper(@metadata, @payload)
    end

    describe "when a StandardError-like error is raised" do
      before(:each) do
        @consumer.stub(:handle_message).and_raise(StandardError)
      end

      it "should be caught" do
        expect {
          @consumer.handle_message_wrapper(@metadata, @payload)
        }.to_not raise_error
      end

      it "should log" do
        AMQP::Boilerplate.logger.should_receive(:error)
        @consumer.handle_message_wrapper(@metadata, @payload)
      end
    end

    describe "when a NotImplementedError is raised" do
      before(:each) do
        @consumer.stub(:handle_message).and_raise(NotImplementedError)
      end

      it "should not be caught" do
        expect {
          @consumer.handle_message_wrapper(@metadata, @payload)
        }.to raise_error(NotImplementedError)
      end
    end
  end
end
