require "helper"

class PagerduryOutputTest < Test::Unit::TestCase
  setup do
    @tmpdir = File.join(Dir.tmpdir, "pagerduty-buffer")
    Fluent::Test.setup
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  def create_driver(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::PagerdutyOutput).configure(conf)
  end

  sub_test_case "process" do
    test "simple" do
      conf = %[
        service_key xxx
        description test
        <buffer tag>
          path #{@tmpdir}
        </buffer>
      ]
      d = create_driver(conf)
      record = { "log" => "This is test" }
      api = mock(Object.new).trigger("test", { "details" => record })
      mock(Pagerduty).new("xxx") { api }
      d.run(default_tag: "test.tag") do
        d.feed(record)
      end
    end

    test "incident_key" do
      conf = %[
        service_key xxx
        description test
        incident_key incident
        <buffer tag>
          path #{@tmpdir}
        </buffer>
      ]
      d = create_driver(conf)
      record = { "log" => "This is test", "incident" => "serious" }
      api = mock(Object.new).trigger("test", { "details" => record })
      mock(PagerdutyIncident).new("xxx", "incident") { api }
      d.run(default_tag: "test.tag") do
        d.feed(record)
      end
    end

    sub_test_case "placeholder" do
      test "description" do
        conf = %[
          service_key xxx
          description dummy.${tag}.${level}
          <buffer tag,level>
            path #{@tmpdir}
          </buffer>
        ]
        d = create_driver(conf)
        record = { "log" => "This is test", "incident" => "serious", "level" => "INFO" }
        api = mock(Object.new).trigger("dummy.test.tag.INFO", { "details" => record })
        mock(Pagerduty).new("xxx") { api }
        d.run(default_tag: "test.tag") do
          d.feed(record)
        end
      end

      test "nested record" do
        conf = %[
          service_key xxx
          description Alarm@${$.Node.Location}:: ${$.Log.Message}
          incident_key ${tag[1]} ${$.Log.File}:${$.Log.Line}
          <buffer tag,$.Log.File,$.Log.Line,$.Log.Message,$.Node.Location>
            path #{@tmpdir}
          </buffer>
      ]
        d = create_driver(conf)
        record = {
          "Node" => {
            "Location" => "Somewhere",
            "IP Address" => "10.0.0.1"
          },
          "Log" => {
            "Level" => "ERROR",
            "File" => "FooBar.cpp",
            "Line" => 42,
            "Message" => "A very important logging message"
          }
        }
        description = "Alarm@Somewhere:: A very important logging message"
        incident_key = "pagerduty FooBar.cpp:42"
        api = mock(Object.new).trigger(description, { "details" => record })
        mock(PagerdutyIncident).new("xxx", incident_key) { api }
        d.run(default_tag: "notify.pagerduty") do
          d.feed(record)
        end
      end
    end
  end
end
