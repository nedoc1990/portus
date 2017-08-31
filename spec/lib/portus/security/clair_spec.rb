require "rails_helper"
require "portus/security"

def expect_cve_match(cves, given, expected)
  cves.each do |cve|
    r = given.find { |x| x["Name"] == cve }
    e = expected.find { |x| x["Name"] == cve }

    expect(r).to include(e)
  end
end

describe ::Portus::SecurityBackend::Clair do
  before :each do
    APP_CONFIG["security"] = {
      "clair" => {
        "server" => "http://my.clair:6060"
      }, "zypper" => {
        "server" => ""
      }, "dummy" => {
        "server" => ""
      }
    }
  end

  let!(:reg) do
    create(
      :registry,
      name:     "registry",
      hostname: "registry.test.cat:5000",
      use_ssl:  true
    )
  end

  let(:proper) do
    {
      clair: [
        {
          "Name"          => "CVE-2016-8859",
          "NamespaceName" => "alpine:v3.4",
          "Link"          => "https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2016-8859",
          "Severity"      => "High",
          "Metadata"      => {
            "NVD" => {
              "CVSSv2" => {
                "Score"   => 7.5,
                "Vectors" => "AV:N/AC:L/Au:N/C:P/I:P"
              }
            }
          },
          "FixedBy"       => "1.1.14-r13"
        },
        {
          "Name"          => "CVE-2016-6301",
          "NamespaceName" => "alpine:v3.4",
          "Link"          => "https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2016-6301",
          "Severity"      => "High",
          "Metadata"      => {
            "NVD" => {
              "CVSSv2" => {
                "Score"   => 7.8,
                "Vectors" => "AV:N/AC:L/Au:N/C:N/I:N"
              }
            }
          },
          "FixedBy"       => "1.24.2-r12"
        }
      ]
    }.freeze
  end

  it "returns CVEs successfully" do
    VCR.turn_on!
    res = {}

    VCR.use_cassette("security/clair", record: :none) do
      clair = ::Portus::Security.new("coreos/dex", "unrelated")
      res = clair.vulnerabilities
    end

    expect_cve_match(["CVE-2016-6301", "CVE-2016-8859"], res[:clair], proper[:clair])
  end

  it "logs the proper debug message when posting is unsuccessful" do
    VCR.turn_on!
    res = {}

    msg = "Could not post "\
          "'sha256:28c417e954d8f9d2439d5b9c7ea3dcb2fd31690bf2d79b94333d889ea26689d2':"\
          " Something went wrong when posting"
    expect(Rails.logger).to receive(:debug).with(msg)

    VCR.use_cassette("security/clair-wrong-post", record: :none) do
      clair = ::Portus::Security.new("coreos/dex", "unrelated")
      res = clair.vulnerabilities
    end

    expect(res[:clair]).to be_empty
  end

  it "logs the proper debug message when fetching is unsuccessful" do
    VCR.turn_on!
    res = {}

    msg = "Error for "\
          "'sha256:28c417e954d8f9d2439d5b9c7ea3dcb2fd31690bf2d79b94333d889ea26689d2':"\
          " Something went wrong when fetching"
    expect(Rails.logger).to receive(:debug).with(msg)

    VCR.use_cassette("security/clair-wrong-get", record: :none) do
      clair = ::Portus::Security.new("coreos/dex", "unrelated")
      res = clair.vulnerabilities
    end

    expect(res[:clair]).to be_empty
  end

  it "returns an empty array if clair is not accessible" do
    APP_CONFIG["security"]["clair"]["server"] = "http://localhost:6060"

    VCR.turn_on!
    res = {}

    VCR.use_cassette("security/clair-is-not-there", record: :none) do
      clair = ::Portus::Security.new("coreos/dex", "unrelated")
      res = clair.vulnerabilities
    end

    expect(res[:clair]).to be_empty
  end

  it "returns an empty array if clair is unknown" do
    VCR.turn_on!
    res = {}

    # Digest as returned by the VCR tape.
    digest = "sha256:28c417e954d8f9d2439d5b9c7ea3dcb2fd31690bf2d79b94333d889ea26689d2"

    # Unfortunately VCR is not good with requests that are meant to time
    # out. For this, then, we will manually stub requests so they raise the
    # expected error on this situation.
    stub_request(:post, "http://my.clair:6060/v1/layers").to_raise(Errno::ECONNREFUSED)
    stub_request(:get, "http://my.clair:6060/v1/layers/#{digest}?" \
                       "features=false&vulnerabilities=true").to_raise(Errno::ECONNREFUSED)

    VCR.use_cassette("security/clair-is-unknown", record: :none) do
      clair = ::Portus::Security.new("coreos/dex", "unrelated")
      res = clair.vulnerabilities
    end

    expect(res[:clair]).to be_empty
  end
end
