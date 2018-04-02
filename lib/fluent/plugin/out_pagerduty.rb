require 'pagerduty'
require 'fluent/plugin/output'

class Fluent::Plugin::PagerdutyOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('pagerduty', self)

  config_param :service_key, :string, secret: true
  config_param :event_type, :string, default: 'trigger'
  config_param :description, :string, default: nil
  config_param :incident_key, :string, default: nil

  config_section :buffer do
    config_set_default :@type, :file
    config_set_default :chunk_keys, ['tag']
    config_set_default :flush_interval, 0
  end

  def configure(conf)
    super

    # PagerDuty trigger event type requires description, other event types do not
    if @description.nil?
      $log.warn "pagerduty: description required for trigger event_type."
    end
  end

  def write(chunk)
    metadata = chunk.metadata
    chunk.each do |time, record|
      call_pagerduty(metadata, record)
    end
  end

  def multi_workers_ready?
    true
  end

  def call_pagerduty(metadata, record)
    begin
      description = record['description'] || record['message'] || @description
      incident_key = record['incident_key'] || @incident_key
      details = record['details'] || record
      options = {"details" => details}
      
      description = extract_placeholders(description, metadata)
      
      if !@incident_key.nil?
        incident_key = extract_placeholders(incident_key, metadata)
        api = PagerdutyIncident.new(@service_key, incident_key)
      else
        api = Pagerduty.new(@service_key)
      end

      api.trigger description, options
    rescue PagerdutyException => e
      log.error "pagerduty: request failed. ", error_class: e.class, error: e.message
    end
  end
end
