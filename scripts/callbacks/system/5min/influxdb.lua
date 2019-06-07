--
-- (C) 2013-19 - ntop.org
--

local ts_utils = require("ts_utils_core")

local probe = {
  name = "InfluxDB",
  description = "Monitors InfluxDB health and performance",
}

-- ##############################################

local function get_storage_size_query(influxdb, schema, tstart, tend, time_step)
  local q = 'SELECT SUM(disk_bytes) as disk_bytes from (SELECT MEAN(diskBytes) as disk_bytes' ..
      ' FROM "monitor"."shard" where "database"=\''.. influxdb.db ..'\' group by id, TIME('.. time_step ..'s)) WHERE ' ..
      " time >= " .. tstart .. "000000000 AND time <= " .. tend .. "000000000" ..
      " GROUP BY TIME(".. time_step .."s)"

  return(q)
end

-- ##############################################

function probe.isEnabled()
  return(ts_utils.getDriverName() == "influxdb")
end

-- ##############################################

function probe.loadSchemas(ts_utils)
  local influxdb = ts_utils.getQueryDriver()
  local schema

  schema = ts_utils.newSchema("influxdb:rtt", {label = i18n("graphs.num_ms_rtt"), metrics_type = ts_utils.metrics.gauge})
  schema:addMetric("millis_rtt")

  -- The following metrics are built-in into influxdb
  schema = ts_utils.newSchema("influxdb:storage_size", {
    label = i18n("traffic_recording.storage"), influx_internal_query = get_storage_size_query,
    metrics_type = ts_utils.metrics.gauge, step = 10
  })
  schema:addMetric("disk_bytes")
end

-- ##############################################

function probe.runTask(when, ts_utils)
  local influxdb = ts_utils.getQueryDriver()
  local start_ms = ntop.gettimemsec()
  local res = influxdb:getInfluxdbVersion()

  if res ~= nil then
    local end_ms = ntop.gettimemsec()

    ts_utils.append("influxdb:rtt", {millis_rtt = ((end_ms-start_ms)*1000)}, when)
  end
end

-- ##############################################

return probe