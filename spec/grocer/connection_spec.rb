require 'spec_helper'
require 'grocer/connection'

describe Grocer::Connection do
  subject { described_class.new(connection_options) }
  let(:connection_options) { { certificate: '/path/to/cert.pem',
                               gateway: 'push.example.com',
                               port: 443 } }
  let(:ssl) { stub_everything('SSLConnection') }
  let(:nonblock_exception) do
    Errno::EWOULDBLOCK.new.extend(IO::WaitReadable)
  end

  before do
    Grocer::SSLConnection.stubs(:new).returns(ssl)
  end

  it 'can be initialized with a certificate' do
    expect(subject.certificate).to eq('/path/to/cert.pem')
  end

  it 'defaults to an empty passphrase' do
    expect(subject.passphrase).to be_nil
  end

  it 'can be initialized with a passphrase' do
    connection_options[:passphrase] = 'new england clam chowder'
    expect(subject.passphrase).to eq('new england clam chowder')
  end

  it 'requires a gateway' do
    connection_options.delete(:gateway)
    -> { described_class.new(connection_options) }.should raise_error(Grocer::NoGatewayError)
  end

  it 'can be initialized with a gateway' do
    expect(subject.gateway).to eq('push.example.com')
  end

  it 'requires a port' do
    connection_options.delete(:port)
    -> { described_class.new(connection_options) }.should raise_error(Grocer::NoPortError)
  end

  it 'can be initialized with a port' do
    expect(subject.port).to eq(443)
  end

  it 'can open the connection to the apple push notification service' do
    subject.connect
    ssl.should have_received(:connect)
  end

  it 'raises CertificateExpiredError for OpenSSL::SSL::SSLError with /certificate expired/i message' do
    ssl.stubs(:read_nonblock).raises(nonblock_exception)
    ssl.stubs(:write).raises(OpenSSL::SSL::SSLError.new('certificate expired'))
    -> {subject.write('abc123')}.should raise_error(Grocer::CertificateExpiredError)
  end

  it 'raises ErrorResponse when there is a response on the socket' do
    ssl.stubs(:read_nonblock).returns("\b\x00\x00\x00\x00\x00")
    -> {subject.write('abc123')}.should raise_error(Grocer::ErrorResponse)
  end

  context 'an open SSLConnection' do
    before do
      ssl.stubs(:read_nonblock).raises(nonblock_exception)
      ssl.stubs(:connected?).returns(true)
    end

    it '#write delegates to open SSLConnection' do
      subject.write('Apples to Oranges')
      ssl.should have_received(:write).with('Apples to Oranges')
    end

    it '#read delegates to open SSLConnection' do
      subject.read(42, 'IO')
      ssl.should have_received(:read).with(42, 'IO')
    end
  end

  context 'a closed SSLConnection' do
    before do
      ssl.stubs(:read_nonblock).raises(nonblock_exception)
      ssl.stubs(:connected?).returns(false)
    end

    it '#write connects SSLConnection and delegates to it' do
      subject.write('Apples to Oranges')
      ssl.should have_received(:connect)
      ssl.should have_received(:write).with('Apples to Oranges')
    end

    it '#read connects SSLConnection delegates to open SSLConnection' do
      subject.read(42, 'IO')
      ssl.should have_received(:connect)
      ssl.should have_received(:read).with(42, 'IO')
    end
  end
end
