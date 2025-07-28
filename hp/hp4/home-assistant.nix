#
# home-assistant.nix
#
# https://nixos.wiki/wiki/Home_Assistant
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/home-assistant/default.nix
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/home-assistant/component-packages.nix
#
# https://nathan.gs/2023/12/28/home-assistant-add-a-custom-component-in-nixos-revisited/
# https://github.com/nathan-gs/nix-conf/blob/main/services/home-assistant.nix
#
{ config, pkgs, ... }:
{
  # sudo systemctl restart home-assistant.service
  services.home-assistant = {
    enable = true;

    # package = (pkgs.home-assistant.override {
    #   extraPackages = py: with py; [ psycopg2 ];
    # }).overrideAttrs (oldAttrs: {
    #   doInstallCheck = false;
    # });

    # nix package zigbee2mqtt_2
    # https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=mqtt


    # https://github.com/NixOS/nixpkgs/tree/master/pkgs/servers/home-assistant/custom-components/
    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "homekit"
      #"met"
      "radio_browser"
      "tuya"
      "wemo"
      "api"
      "apple_tv"
      "bluetooth"
      "http"
      "html5"
      "ping"
      "scrape"
      "sensor"
      "smartthings"
      "openweathermap"
      "samsungtv"
      "prometheus"
      "roborock"
      "litterrobot"
      "nest"
      "zeroconf"
      "speedtestdotnet"
      "unifi"
      "unifi_direct"
      "mqtt"
      "mqtt_eventstream"
      "mqtt_json"
      "mqtt_room"
      "mqtt_statestream"
      "zha"
    ];

    # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/home-assistant/python-modules/hass-web-proxy-lib/default.nix
    extraPackages = python3Packages: with python3Packages; [
      # recorder postgresql support
      psycopg2

      aiohomekit
      aiohttp
      aiohttp-fast-zlib

      # Performance libraries for aiohttp
      isal
      zlib-ng

      # Optional extras that might be pulled by integrations
      orjson
      ciso8601
      yarl
      multidict

      universal-silabs-flasher
      zha-quirks
      zigpy-deconz
      zigpy-xbee
      zigpy-zigate
      zigpy-znp

      getmac
      hap-python
      pyipp
      pyotp
      pyqrcode
    ];

    #configDir = /var/lib/hass;
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
      recorder = {
        db_url = "postgresql://@/hass";
        purge_keep_days = 3650;
        auto_purge = true;
        auto_repack = true;
      };
    };
  };

  # https://nixos.wiki/wiki/Home_Assistant#Using_PostgreSQL
  # sudo systemctl restart postgresql.service
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "hass" ];
    ensureUsers = [{
      name = "hass";
      ensureDBOwnership = true;
    }];
  };

  # systemd.tmpfiles.rules = [
  #   #"C ${config.services.home-assistant.configDir}/custom_components/sonoff - - - - ${sources.sonoff-lan}/custom_components/sonoff"
  #   "Z ${config.services.home-assistant.configDir}/custom_components 770 hass hass - -"
  #   "f ${config.services.home-assistant.configDir}/automations.yaml 0755 hass hass"
  # ];
}

#error: A definition for option `services.home-assistant.extraComponents."[definition 1-entry 15]"' is not of type `one of "3_day_blinds", "abode", "accuweather", "acer_projector", "acmeda", "acomax", "actiontec", "adax", "adguard", "ads", "advantage_air", "aemet", "aep_ohio", "aep_texas", "aftership", "agent_dvr", "air_quality", "airgradient", "airly", "airnow", "airq", "airthings", "airthings_ble", "airtouch4", "airtouch5", "airvisual", "airvisual_pro", "airzone", "airzone_cloud", "aladdin_connect", "alarm_control_panel", "alarmdecoder", "alert", "alexa", "alpha_vantage", "amazon_polly", "amberelectric", "ambient_network", "ambient_station", "amcrest", "amp_motorization", "ampio", "analytics", "analytics_insights", "android_ip_webcam", "androidtv", "androidtv_remote", "anel_pwrctrl", "anova", "anthemav", "anthropic", "anwb_energie", "aosmith", "apache_kafka", "apcupsd", "api", "appalachianpower", "apple_tv", "application_credentials", "apprise", "aprilaire", "aprs", "aps", "apsystems", "aquacell", "aqualogic", "aquostv", "aranet", "arcam_fmj", "arest", "arris_tg2492lg", "artsound", "aruba", "arve", "arwn", "aseko_pool_live", "assist_pipeline", "assist_satellite", "asuswrt", "atag", "aten_pe", "atlanticcityelectric", "atome", "august", "august_ble", "aurora", "aurora_abb_powerone", "aussie_broadband", "autarco", "auth", "automation", "avea", "avion", "awair", "aws", "axis", "azure_data_explorer", "azure_devops", "azure_event_hub", "azure_service_bus", "backup", "baf", "baidu", "balboa", "bang_olufsen", "bayesian", "bbox", "beewi_smartclim", "bge", "binary_sensor", "bitcoin", "bizkaibus", "blackbird", "blebox", "blink", "bliss_automation", "bloc_blinds", "blockchain", "blue_current", "bluemaestro", "blueprint", "bluesound", "bluetooth", "bluetooth_adapters", "bluetooth_le_tracker", "bluetooth_tracker", "bmw_connected_drive", "bond", "bosch_shc", "brandt", "braviatv", "brel_home", "bring", "broadlink", "brother", "brottsplatskartan", "browser", "brunt", "bryant_evolution", "bsblan", "bswitch", "bt_home_hub_5", "bt_smarthub", "bthome", "bticino", "bubendorff", "buienradar", "button", "caldav", "calendar", "cambridge_audio", "camera", "canary", "cast", "ccm15", "cert_expiry", "chacon_dio", "channels", "cisco_ios", "cisco_mobility_express", "cisco_webex_teams", "citybikes", "clementine", "clickatell", "clicksend", "clicksend_tts", "climate", "cloud", "cloudflare", "cmus", "co2signal", "coautilities", "coinbase", "color_extractor", "comed", "comed_hourly_pricing", "comelit", "comfoconnect", "command_line", "compensation", "concord232", "coned", "config", "configurator", "control4", "conversation", "coolmaster", "counter", "cover", "cozytouch", "cppm_tracker", "cpuspeed", "cribl", "crownstone", "cups", "currencylayer", "dacia", "daikin", "danfoss_air", "datadog", "date", "datetime", "ddwrt", "deako", "debugpy", "deconz", "decora", "decora_wifi", "default_config", "delijn", "delmarva", "deluge", "demo", "denon", "denonavr", "derivative", "devialet", "device_automation", "device_sun_light_trigger", "device_tracker", "devolo_home_control", "devolo_home_network", "dexcom", "dhcp", "diagnostics", "dialogflow", "diaz", "digital_loggers", "digital_ocean", "directv", "discogs", "discord", "discovergy", "dlib_face_detect", "dlib_face_identify", "dlink", "dlna_dmr", "dlna_dms", "dnsip", "dominos", "doods", "doorbird", "dooya", "dormakaba_dkey", "downloader", "dremel_3d_printer", "drop_connect", "dsmr", "dsmr_reader", "dte_energy_bridge", "dublin_bus_transport", "duckdns", "duke_energy", "dunehd", "duotecno", "duquesne_light", "dwd_weather_warnings", "dweet", "dynalite", "eafm", "eastron", "easyenergy", "ebox", "ebusd", "ecoal_boiler", "ecobee", "ecoforest", "econet", "ecovacs", "ecowitt", "eddystone_temperature", "edimax", "edl21", "efergy", "egardia", "eight_sleep", "electrasmart", "electric_kiwi", "elevenlabs", "elgato", "eliqonline", "elkm1", "elmax", "elv", "elvia", "emby", "emoncms", "emoncms_history", "emonitor", "emulated_hue", "emulated_kasa", "emulated_roku", "energenie_power_sockets", "energie_vanons", "energy", "energyzero", "enigma2", "enmax", "enocean", "enphase_envoy", "entur_public_transport", "environment_canada", "envisalink", "ephember", "epic_games_store", "epion", "epson", "eq3btsmart", "escea", "esera_onewire", "esphome", "etherscan", "eufy", "eufylife_ble", "event", "evergy", "everlights", "evil_genius_labs", "evohome", "ezviz", "faa_delays", "facebook", "fail2ban", "familyhub", "fan", "fastdotcom", "feedreader", "ffmpeg", "ffmpeg_motion", "ffmpeg_noise", "fibaro", "fido", "file", "file_upload", "filesize", "filter", "fints", "fire_tv", "fireservicerota", "firmata", "fitbit", "fivem", "fixer", "fjaraskupan", "fleetgo", "flexit", "flexit_bacnet", "flexom", "flic", "flick_electric", "flipr", "flo", "flock", "flume", "flux", "flux_led", "folder", "folder_watcher", "foobot", "forecast_solar", "forked_daapd", "fortios", "foscam", "foursquare", "free_mobile", "freebox", "freedns", "freedompro", "fritz", "fritzbox", "fritzbox_callmonitor", "fronius", "frontend", "frontier_silicon", "fujitsu_anywair", "fujitsu_fglair", "fully_kiosk", "futurenow", "fyta", "garadget", "garages_amsterdam", "gardena_bluetooth", "gaviota", "gc100", "gdacs", "generic", "generic_hygrostat", "generic_thermostat", "geniushub", "geo_json_events", "geo_location", "geo_rss_events", "geocaching", "geofency", "geonetnz_quakes", "geonetnz_volcano", "gios", "github", "gitlab_ci", "gitter", "glances", "go2rtc", "goalzero", "gogogate2", "goodwe", "google", "google_assistant", "google_assistant_sdk", "google_cloud", "google_generative_ai_conversation", "google_mail", "google_maps", "google_photos", "google_pubsub", "google_sheets", "google_tasks", "google_translate", "google_travel_time", "google_wifi", "govee_ble", "govee_light_local", "gpsd", "gpslogger", "graphite", "gree", "greeneye_monitor", "greenwave", "group", "growatt_server", "gstreamer", "gtfs", "guardian", "habitica", "hardkernel", "hardware", "harman_kardon_avr", "harmony", "hassio", "havana_shade", "haveibeenpwned", "hddtemp", "hdmi_cec", "heatmiser", "heiwa", "heos", "here_travel_time", "hexaom", "hi_kumo", "hikvision", "hikvisioncam", "hisense_aehw4a1", "history", "history_stats", "hitron_coda", "hive", "hko", "hlk_sw16", "holiday", "home_connect", "home_plus_control", "homeassistant", "homeassistant_alerts", "homeassistant_green", "homeassistant_hardware", "homeassistant_sky_connect", "homeassistant_yellow", "homekit", "homekit_controller", "homematic", "homematicip_cloud", "homewizard", "homeworks", "honeywell", "horizon", "hp_ilo", "html5", "http", "huawei_lte", "hue", "huisbaasje", "humidifier", "hunterdouglas_powerview", "hurrican_shutters_wholesale", "husqvarna_automower", "husqvarna_automower_ble", "huum", "hvv_departures", "hydrawise", "hyperion", "ialarm", "iammeter", "iaqualink", "ibeacon", "icloud", "idasen_desk", "idteck_prox", "ifttt", "iglo", "ign_sismologia", "ihc", "image", "image_processing", "image_upload", "imap", "imgw_pib", "improv_ble", "incomfort", "indianamichiganpower", "influxdb", "inkbird", "input_boolean", "input_button", "input_datetime", "input_number", "input_select", "input_text", "inspired_shades", "insteon", "integration", "intellifire", "intent", "intent_script", "intesishome", "ios", "iotawatt", "iotty", "iperf3", "ipma", "ipp", "iqvia", "irish_rail_transport", "iron_os", "isal", "iskra", "islamic_prayer_times", "ismartwindow", "israel_rail", "iss", "ista_ecotrend", "isy994", "itach", "itunes", "izone", "jellyfin", "jewish_calendar", "joaoapps_join", "juicenet", "justnimbus", "jvc_projector", "kaiterra", "kaleidescape", "kankun", "keba", "keenetic_ndms2", "kef", "kegtron", "kentuckypower", "keyboard", "keyboard_remote", "keymitt_ble", "kira", "kitchen_sink", "kiwi", "kmtronic", "knocki", "knx", "kodi", "konnected", "kostal_plenticore", "kraken", "krispol", "kulersky", "kwb", "lacrosse", "lacrosse_view", "lamarzocco", "lametric", "landisgyr_heat_meter", "lannouncer", "lastfm", "launch_library", "laundrify", "lawn_mower", "lcn", "ld2410_ble", "leaone", "led_ble", "legrand", "lektrico", "lg_netcast", "lg_soundbar", "lg_thinq", "lidarr", "life360", "lifx", "lifx_cloud", "light", "lightwave", "limitlessled", "linear_garage_door", "linkplay", "linksys_smart", "linode", "linux_battery", "lirc", "litejet", "litterrobot", "livisi", "llamalab_automate", "local_calendar", "local_file", "local_ip", "local_todo", "locative", "lock", "logbook", "logentries", "logger", "london_air", "london_underground", "lookin", "loqed", "lovelace", "luci", "luftdaten", "lupusec", "lutron", "lutron_caseta", "luxaflex", "lw12wifi", "lyric", "madeco", "madvr", "mailgun", "manual", "manual_mqtt", "marantz", "martec", "marytts", "mastodon", "matrix", "matter", "maxcube", "mazda", "mealie", "meater", "medcom_ble", "media_extractor", "media_player", "media_source", "mediaroom", "melcloud", "melissa", "melnor", "meraki", "mercury_nz", "message_bird", "met", "met_eireann", "meteo_france", "meteoalarm", "meteoclimatic", "metoffice", "mfi", "microbees", "microsoft", "microsoft_face", "microsoft_face_detect", "microsoft_face_identify", "mijndomein_energie", "mikrotik", "mill", "min_max", "minecraft_server", "mini_connected", "minio", "mjpeg", "moat", "mobile_app", "mochad", "modbus", "modem_callerid", "modern_forms", "moehlenhoff_alpha2", "mold_indicator", "monarch_money", "monessen", "monoprice", "monzo", "moon", "mopeka", "motion_blinds", "motionblinds_ble", "motioneye", "motionmount", "mpd", "mqtt", "mqtt_eventstream", "mqtt_json", "mqtt_room", "mqtt_statestream", "msteams", "mullvad", "mutesync", "my", "myq", "mysensors", "mystrom", "mythicbeastsdns", "myuplink", "nad", "nam", "namecheapdns", "nanoleaf", "neato", "nederlandse_spoorwegen", "ness_alarm", "nest", "netatmo", "netdata", "netgear", "netgear_lte", "netio", "network", "neurio_energy", "nexia", "nexity", "nextbus", "nextcloud", "nextdns", "nfandroidtv", "nibe_heatpump", "nice_go", "nightscout", "niko_home_control", "nilu", "nina", "nissan_leaf", "nmap_tracker", "nmbs", "no_ip", "noaa_tides", "nobo_hub", "norway_air", "notify", "notify_events", "notion", "nsw_fuel_station", "nsw_rural_fire_service_feed", "nuheat", "nuki", "numato", "number", "nut", "nutrichef", "nws", "nx584", "nyt_games", "nzbget", "oasa_telematics", "obihai", "octoprint", "oem", "ohmconnect", "ollama", "ombi", "omnilogic", "onboarding", "oncue", "ondilo_ico", "onewire", "onkyo", "onvif", "open_meteo", "openai_conversation", "openalpr_cloud", "openerz", "openevse", "openexchangerates", "opengarage", "openhardwaremonitor", "openhome", "opensensemap", "opensky", "opentherm_gw", "openuv", "openweathermap", "opnsense", "opower", "opple", "oralb", "oru", "oru_opower", "orvibo", "osoenergy", "osramlightify", "otbr", "otp", "ourgroceries", "overkiz", "ovo_energy", "owntracks", "p1_monitor", "palazzetti", "panasonic_bluray", "panasonic_viera", "pandora", "panel_custom", "pcs_lighting", "peco", "peco_opower", "pegel_online", "pencom", "pepco", "permobil", "persistent_notification", "person", "pge", "philips_js", "pi_hole", "picnic", "picotts", "pilight", "pinecil", "ping", "pioneer", "piper", "pjlink", "plaato", "plant", "plex", "plugwise", "plum_lightpad", "pocketcasts", "point", "poolsense", "portlandgeneral", "powerwall", "private_ble_device", "profiler", "progettihwsw", "proliphix", "prometheus", "prosegur", "prowl", "proximity", "proxmoxve", "proxy", "prusalink", "ps4", "pse", "psoklahoma", "pulseaudio_loopback", "pure_energie", "purpleair", "push", "pushbullet", "pushover", "pushsafer", "pvoutput", "pvpc_hourly_pricing", "pyload", "python_script", "qbittorrent", "qingping", "qld_bushfire", "qnap", "qnap_qsw", "qrcode", "quadrafire", "quantum_gateway", "qvr_pro", "qwikswitch", "rabbitair", "rachio", "radarr", "radio_browser", "radiotherm", "rainbird", "raincloud", "rainforest_eagle", "rainforest_raven", "rainmachine", "random", "rapt_ble", "raspberry_pi", "raspyrfm", "raven_rock_mfg", "rdw", "recollect_waste", "recorder", "recovery_mode", "recswitch", "reddit", "refoss", "rejseplanen", "remember_the_milk", "remote", "remote_rpi_gpio", "renault", "renson", "reolink", "repairs", "repetier", "rest", "rest_command", "rexel", "rflink", "rfxtrx", "rhasspy", "ridwell", "ring", "ripple", "risco", "rituals_perfume_genie", "rmvtransport", "roborock", "rocketchat", "roku", "romy", "roomba", "roon", "route53", "rova", "rpi_camera", "rpi_power", "rss_feed_template", "rtorrent", "rtsp_to_webrtc", "ruckus_unleashed", "russound_rio", "russound_rnet", "ruuvi_gateway", "ruuvitag_ble", "rympro", "sabnzbd", "saj", "samsam", "samsungtv", "sanix", "satel_integra", "scene", "schedule", "schlage", "schluter", "scl", "scrape", "screenaway", "screenlogic", "script", "scsgate", "search", "season", "select", "sendgrid", "sense", "sensibo", "sensirion_ble", "sensor", "sensorblue", "sensorpro", "sensorpush", "sensoterra", "sentry", "senz", "serial", "serial_pm", "sesame", "seven_segments", "seventeentrack", "sfr_box", "sharkiq", "shell_command", "shelly", "shodan", "shopping_list", "sia", "sigfox", "sighthound", "signal_messenger", "simplefin", "simplepush", "simplisafe", "simply_automated", "simu", "simulated", "sinch", "siren", "sisyphus", "sky_hub", "skybeacon", "skybell", "slack", "sleepiq", "slide", "slimproto", "sma", "smappee", "smart_blinds", "smart_home", "smart_meter_texas", "smarther", "smartthings", "smarttub", "smarty", "smhi", "smlight", "sms", "smtp", "smud", "snapcast", "snips", "snmp", "snooz", "solaredge", "solaredge_local", "solarlog", "solax", "soma", "somfy", "somfy_mylink", "sonarr", "songpal", "sonos", "sony_projector", "soundtouch", "spaceapi", "spc", "speedtestdotnet", "spider", "splunk", "spotify", "sql", "squeezebox", "srp_energy", "ssdp", "starline", "starlingbank", "starlink", "startca", "statistics", "statsd", "steam_online", "steamist", "stiebel_eltron", "stookalert", "stookwijzer", "stream", "streamlabswater", "stt", "subaru", "suez_water", "sun", "sunweg", "supervisord", "supla", "surepetcare", "swepco", "swiss_hydrological_data", "swiss_public_transport", "swisscom", "switch", "switch_as_x", "switchbee", "switchbot", "switchbot_cloud", "switcher_kis", "switchmate", "symfonisk", "syncthing", "syncthru", "synology_chat", "synology_dsm", "synology_srm", "syslog", "system_bridge", "system_health", "system_log", "systemmonitor", "tado", "tag", "tailscale", "tailwind", "tami4", "tank_utility", "tankerkoenig", "tapsaff", "tasmota", "tautulli", "tcp", "technove", "ted5000", "tedee", "telegram", "telegram_bot", "tellduslive", "tellstick", "telnet", "temper", "template", "tensorflow", "tesla_fleet", "tesla_wall_connector", "teslemetry", "tessie", "text", "thermobeacon", "thermoplus", "thermopro", "thethingsnetwork", "thingspeak", "thinkingcleaner", "thomson", "thread", "threshold", "tibber", "tikteck", "tile", "tilt_ble", "time", "time_date", "timer", "tmb", "tod", "todo", "todoist", "tolo", "tomato", "tomorrowio", "toon", "torque", "totalconnect", "touchline", "touchline_sl", "tplink", "tplink_lte", "tplink_omada", "tplink_tapo", "traccar", "traccar_server", "trace", "tractive", "tradfri", "trafikverket_camera", "trafikverket_ferry", "trafikverket_train", "trafikverket_weatherstation", "transmission", "transport_nsw", "travisci", "trend", "triggercmd", "tts", "tuya", "twentemilieu", "twilio", "twilio_call", "twilio_sms", "twinkly", "twitch", "twitter", "ubiwizz", "ubus", "uk_transport", "ukraine_alarm", "ultraloq", "unifi", "unifi_direct", "unifiled", "unifiprotect", "universal", "upb", "upc_connect", "upcloud", "update", "upnp", "uprise_smart_shades", "uptime", "uptimerobot", "usb", "usgs_earthquakes_feed", "utility_meter", "uvc", "v2c", "vacuum", "vallox", "valve", "vasttrafik", "velbus", "velux", "venstar", "vera", "verisure", "vermont_castings", "versasense", "version", "vesync", "viaggiatreno", "vicare", "vilfo", "vivotek", "vizio", "vlc", "vlc_telnet", "vodafone_station", "voicerss", "voip", "volkszaehler", "volumio", "volvooncall", "vulcan", "vultr", "w800rf32", "wake_on_lan", "wake_word", "wallbox", "waqi", "water_heater", "waterfurnace", "watson_iot", "watttime", "waze_travel_time", "weather", "weatherflow", "weatherflow_cloud", "weatherkit", "webhook", "webmin", "webostv", "websocket_api", "weheat", "wemo", "whirlpool", "whisper", "whois", "wiffi", "wilight", "wirelesstag", "withings", "wiz", "wled", "wmspro", "wolflink", "workday", "worldclock", "worldtidesinfo", "worxlandroid", "ws66i", "wsdot", "wyoming", "x10", "xbox", "xeoma", "xiaomi", "xiaomi_aqara", "xiaomi_ble", "xiaomi_miio", "xiaomi_tv", "xmpp", "xs1", "yale", "yale_home", "yale_smart_alarm", "yalexs_ble", "yamaha", "yamaha_musiccast", "yandex_transport", "yandextts", "yardian", "yeelight", "yeelightsunflower", "yi", "yolink", "youless", "youtube", "zabbix", "zamg", "zengge", "zeroconf", "zerproc", "zestimate", "zeversolar", "zha", "zhong_hong", "ziggo_mediabox_xl", "zodiac", "zondergas", "zone", "zoneminder", "zwave_js", "zwave_me"'. Definition values:

# [7103383.054580] usb 2-10: new full-speed USB device number 2 using xhci_hcd
# [7103383.423224] usb 2-10: New USB device found, idVendor=10c4, idProduct=ea60, bcdDevice= 1.00
# [7103383.423241] usb 2-10: New USB device strings: Mfr=1, Product=2, SerialNumber=3
# [7103383.423249] usb 2-10: Product: Sonoff Zigbee 3.0 USB Dongle Plus V2
# [7103383.423256] usb 2-10: Manufacturer: Itead
# [7103383.423262] usb 2-10: SerialNumber: 5cd6337ea3c2ef11ad08c9138148b910
# [7103383.470000] usbcore: registered new interface driver cp210x
# [7103383.470039] usbserial: USB Serial support registered for cp210x
# [7103383.470109] cp210x 2-10:1.0: cp210x converter detected
# [7103383.489117] usb 2-10: cp210x converter now attached to ttyUSB0
# [7185732.178015] Bluetooth: Core ver 2.22
# [7185732.178044] NET: Registered PF_BLUETOOTH protocol family
# [7185732.178046] Bluetooth: HCI device and connection manager initialized
# [7185732.178052] Bluetooth: HCI socket layer initialized
# [7185732.178055] Bluetooth: L2CAP socket layer initialized
# [7185732.178060] Bluetooth: SCO socket layer initialized
# [7189311.168448] usb 2-10: USB disconnect, device number 2
# [7189311.168794] cp210x ttyUSB0: cp210x converter now disconnected from ttyUSB0
# [7189311.172114] cp210x 2-10:1.0: device disconnected
# [7189322.467946] usb 4-2: new full-speed USB device number 2 using xhci_hcd
# [7189322.617268] usb 4-2: New USB device found, idVendor=10c4, idProduct=ea60, bcdDevice= 1.00
# [7189322.617281] usb 4-2: New USB device strings: Mfr=1, Product=2, SerialNumber=3
# [7189322.617287] usb 4-2: Product: Sonoff Zigbee 3.0 USB Dongle Plus V2
# [7189322.617293] usb 4-2: Manufacturer: Itead
# [7189322.617299] usb 4-2: SerialNumber: 5cd6337ea3c2ef11ad08c9138148b910
# [7189322.619534] cp210x 4-2:1.0: cp210x converter detected
# [7189322.628801] usb 4-2: cp210x converter now attached to ttyUSB0