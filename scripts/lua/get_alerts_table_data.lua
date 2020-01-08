--
-- (C) 2013-18 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

require "lua_utils"
require "alert_utils"
require "flow_utils"

local format_utils = require "format_utils"
local json = require "dkjson"
local alerts_api = require "alerts_api"
local alert_consts = require "alert_consts"

sendHTTPHeader('application/json')

local status          = _GET["status"]

local engaged = false
if status == "engaged" then
   engaged = true
end

-- ifid is mandatory here
interface.select(_GET["ifid"])

local ifid = interface.getId()
local entities_bitmaps = {}

local function getEntityAlertDisabledBitmap(entity, entity_val)
  if((entities_bitmaps[entity] ~= nil) and (entities_bitmaps[entity][entity_val] ~= nil)) then
    return entities_bitmaps[entity][entity_val]
  end

  local bitmap = alerts_api.getEntityAlertsDisabledBitmap(ifid, entity, entity_val)
  entities_bitmaps[entity] = entities_bitmaps[entity] or {}
  entities_bitmaps[entity][entity_val] = bitmap

  return(bitmap)
end

--~ function alerts_api.getEntityAlertsDisabled(ifid, entity, entity_val)

if(tonumber(_GET["currentPage"]) == nil) then _GET["currentPage"] = 1 end
if(tonumber(_GET["perPage"]) == nil) then _GET["perPage"] = getDefaultTableSize() end

if(isEmptyString(_GET["sortColumn"]) or (_GET["sortColumn"] == "column_") or (status ~= "historical" and _GET["sortColumn"] == "column_sort")) or (status ~= "historical-flows" and  _GET["sortColumn"] == "column_count") then
   if status ~= "historical-flows" and  _GET["sortColumn"] == "column_count" then
      tablePreferences("sort_alerts", "column_")
   end
   _GET["sortColumn"] = getDefaultTableSort("alerts")
elseif((_GET["sortColumn"] ~= "column_") and (_GET["sortColumn"] ~= "")) then
   tablePreferences("sort_alerts", _GET["sortColumn"])
end

if _GET["sortOrder"] == nil then
   _GET["sortOrder"] = getDefaultTableSortOrder("alerts")
elseif((_GET["sortColumn"] == "column_") or (_GET["sortOrder"] == "")) then
   _GET["sortOrder"] = "asc"
end
tablePreferences("sort_order_alerts", _GET["sortOrder"])

local alert_options = _GET

if alert_options.entity_val ~= nil then
   alert_options.entity_val = string.gsub(alert_options.entity_val, "http:__", "http://")
   alert_options.entity_val = string.gsub(alert_options.entity_val, "https:__", "https://")
end

local alerts, num_alerts = getAlerts(status, alert_options, true --[[ with_counters ]])

if alerts == nil then alerts = {} end

local res_formatted = {}

for _key,_value in ipairs(alerts) do
   local record = {}
   local alert_entity
   local alert_entity_val
   local column_duration = ""
   local tdiff = os.time()-_value["alert_tstamp"]
   local column_date = os.date("%c", _value["alert_tstamp"])

   local alert_id        = _value["rowid"]

   if _value["alert_entity"] ~= nil then
      alert_entity    = tonumber(_value["alert_entity"])
   else
      alert_entity = "flow" -- flow alerts page doesn't have an entity
   end

   if _value["alert_entity_val"] ~= nil then
      alert_entity_val = _value["alert_entity_val"]
   else
      alert_entity_val = ""
   end

   if(tdiff <= 600) then
      column_date  = secondsToTime(tdiff).. " " ..i18n("details.ago")
   else
      column_date = format_utils.formatPastEpochShort(_value["alert_tstamp"])
   end

   if engaged == true then
      column_duration = secondsToTime(os.time() - tonumber(_value["alert_tstamp"]))
   elseif tonumber(_value["alert_tstamp_end"]) ~= nil 
        and (tonumber(_value["alert_tstamp_end"]) - tonumber(_value["alert_tstamp"])) ~= 0 then
      column_duration = secondsToTime(tonumber(_value["alert_tstamp_end"]) - tonumber(_value["alert_tstamp"]))
   end

   local column_severity = alertSeverityLabel(tonumber(_value["alert_severity"]))
   local column_type     = alertTypeLabel(tonumber(_value["alert_type"]))
   local column_count    = format_utils.formatValue(tonumber(_value["alert_counter"]))
   local column_msg      = string.gsub(formatAlertMessage(ifid, _value), '"', "'")
   local column_chart = nil

   if ntop.isPro() then
      column_chart    = getAlertGraphLink(getInterfaceId(ifname), _value)
      if not isEmptyString(column_chart) then
	 column_chart = "<a href='".. column_chart .."'><i class='fas fa-search-plus drilldown-icon'></i></a>"
      end
   end

   local column_id = tostring(alert_id)

   if ntop.isEnterprise() and (status == "historical-flows") then
      local explore = function()
	 local url = ntop.getHttpPrefix() .. "/lua/pro/enterprise/flow_alerts_explorer.lua?"
	 local origin = _value["cli_addr"]
	 local target = _value["srv_addr"]
	 if origin ~= nil and origin ~= "" then
	    url = url..'&origin='..origin
	 end
	 if target ~= nil and target ~= "" then
	    url = url..'&target='..target
	 end
	 if _value["alert_tstamp"] ~= nil then
	    url = url..'&epoch_begin='..(tonumber(_value["alert_tstamp"]) - 1800)
	    url = url..'&epoch_end='..(tonumber(_value["alert_tstamp"]) + 1800)
	 end
	 return url
      end

      record["column_explorer"] = explore()
   end

   if status ~= "historical-flows" then
     local bitmap = getEntityAlertDisabledBitmap(_value["alert_entity"], _value["alert_entity_val"])

     record["column_entity_formatted"] = alert_consts.formatAlertEntity(ifid, alert_consts.alertEntityRaw(_value["alert_entity"]), _value["alert_entity_val"])
     record["column_alert_disabled"] = ntop.bitmapIsSet(bitmap, tonumber(_value["alert_type"]))
   end

   record["column_key"] = column_id
   record["column_date"] = column_date
   record["column_duration"] = column_duration
   record["column_severity"] = column_severity
   record["column_severity_id"] = tonumber(_value["alert_severity"])
   record["column_subtype"] = _value["alert_subtype"]
   record["column_granularity"] = _value["alert_granularity"]
   record["column_count"] = column_count
   record["column_type"] = column_type
   record["column_type_id"] = tonumber(_value["alert_type"])
   record["column_msg"] = column_msg
   record["column_entity_id"] = alert_entity
   record["column_entity_val"] = alert_entity_val
   record["column_chart"] = column_chart

   res_formatted[#res_formatted + 1] = record
	  
end -- for

local result = {}
result["perPage"] = alert_options.perPage
result["currentPage"] = alert_options.currentPage
result["totalRows"] = num_alerts
result["data"] = res_formatted
result["sort"] = {{alert_options.sortColumn, alert_options.sortOrder}}

print(json.encode(result))

