# Advanced Configuration Guide

Network Quality Monitor can be extensively customized through its configuration files. This document explains the advanced configuration options and their meaning.

## Configuration Files

The application uses two main configuration files:

1. `config.json` - Global application settings and integrations
2. `targets.json` - Target-specific configuration for hosts being monitored

## Global Configuration (config.json)

The `config.json` file follows a hierarchical structure with the following main sections:

### General Settings

```json
"general": {
  "debug_mode": false,
  "log_level": "info",
  "log_directory": "logs",
  "log_retention_days": 7
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `debug_mode` | Boolean | Enable detailed debug output for troubleshooting |
| `log_level` | String | Logging level: "debug", "info", "warning", "error" |
| `log_directory` | String | Directory where log files are stored |
| `log_retention_days` | Number | Number of days to keep log files before deletion |

### Connectivity Configuration

```json
"connectivity": {
  "enabled": true,
  "check_interval": 1,
  "recovery": {
    "grace_period_seconds": 30,
    "reset_statistics_on_recovery": true
  },
  "servers": [
    {
      "host": "1.1.1.1",
      "protocol": "ping",
      "description": "Cloudflare DNS"
    }
  ]
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `enabled` | Boolean | Enable local connectivity checking |
| `check_interval` | Number | How often to check local connectivity, in seconds |
| `recovery.grace_period_seconds` | Number | How long to suppress alerts after connectivity is restored |
| `recovery.reset_statistics_on_recovery` | Boolean | Whether to reset all statistics after connectivity returns |
| `servers` | Array | List of servers to check for connectivity |
| `servers[].host` | String | IP address or hostname to check |
| `servers[].protocol` | String | Protocol to use: "ping", "http", "dns" |
| `servers[].description` | String | Human-readable description |

### Monitoring Settings

```json
"monitoring": {
  "default_settings": {
    "ping_frequency": 1,
    "consecutive_loss_threshold": 2,
    "loss_threshold_pct": 5,
    "report_interval": 10
  }
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `default_settings.ping_frequency` | Number | Default ping frequency in seconds for all targets |
| `default_settings.consecutive_loss_threshold` | Number | How many consecutive lost pings to declare host DOWN |
| `default_settings.loss_threshold_pct` | Number | Percentage loss to trigger an alert |
| `default_settings.report_interval` | Number | How often to generate status reports, in seconds |
| `statistics.reset_interval_hours` | Number | How often to reset the statistics for long-term accuracy |
| `advanced.enable_ttl_monitoring` | Boolean | Whether to monitor TTL changes |
| `advanced.enable_jitter_calculation` | Boolean | Whether to calculate jitter |
| `advanced.enable_mos_calculation` | Boolean | Whether to calculate Mean Opinion Score |

### Notification Settings

```json
"notifications": {
  "event_handlers": {
    "host_down": {
      "enabled": true,
      "retry_interval_seconds": 300,
      "max_alerts_per_hour": 5
    }
  },
  "queue": {
    "enabled": true,
    "directory": "/tmp/network_monitor_alerts",
    "max_age_hours": 24
  }
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `event_handlers.host_down.enabled` | Boolean | Enable notifications for host down events |
| `event_handlers.host_down.retry_interval_seconds` | Number | How often to re-send alerts for hosts that remain down |
| `event_handlers.host_down.max_alerts_per_hour` | Number | Rate limit for alerts per hour |
| `queue.enabled` | Boolean | Enable alert queuing during connectivity loss |
| `queue.directory` | String | Directory for storing queued alerts |
| `queue.max_age_hours` | Number | Maximum time to keep alerts in queue |

### Display Settings

```json
"display": {
  "colors": {
    "enabled": true,
    "rtt": {
      "good_threshold_ms": 80,
      "warning_threshold_ms": 150
    }
  },
  "console": {
    "compact_mode": false,
    "show_alerts_only": false
  }
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `colors.enabled` | Boolean | Enable colored output |
| `colors.rtt.good_threshold_ms` | Number | Threshold in ms for green (good) RTT values |
| `colors.rtt.warning_threshold_ms` | Number | Threshold in ms for yellow (warning) RTT values |
| `console.compact_mode` | Boolean | Use condensed output format |
| `console.show_alerts_only` | Boolean | Only show alerts, not normal status reports |

### Integration Settings

```json
"integrations": {
  "slack": {
    "enabled": false,
    "webhook_url": "https://hooks.slack.com/services/...",
    "default_channel": "#network-alerts"
  }
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `slack.enabled` | Boolean | Enable Slack integration |
| `slack.webhook_url` | String | Slack webhook URL |
| `slack.default_channel` | String | Default Slack channel for notifications |
| `slack.notifications` | Object | Channel overrides for specific alert types |

## Target Configuration (targets.json)

Each target in the `targets.json` file can override global settings:

```json
{
  "targets": [
    {
      "id": "cloudflare-dns",
      "name": "Cloudflare DNS",
      "ip": "1.1.1.1",
      "description": "Cloudflare's primary DNS server",
      "monitoring": {
        "enabled": true,
        "ping_frequency": 1,
        "consecutive_loss_threshold": 2,
        "loss_threshold_pct": 10,
        "report_interval": 10
      }
    }
  ]
}
```

| Setting | Type | Description |
|---------|------|-------------|
| `id` | String | Unique identifier for this target |
| `name` | String | Human-readable name |
| `ip` | String | IP address or hostname to monitor |
| `description` | String | Detailed description of this target |
| `monitoring.enabled` | Boolean | Whether monitoring is active for this target |
| `monitoring.ping_frequency` | Number | How often to ping, in seconds |
| `monitoring.consecutive_loss_threshold` | Number | How many consecutive losses to declare DOWN |
| `monitoring.loss_threshold_pct` | Number | Loss percentage to trigger alert |
| `monitoring.report_interval` | Number | Status report interval in seconds |
| `thresholds` | Object | Target-specific thresholds for metrics |
| `notifications` | Object | Target-specific notification settings |

### Target Groups

Target groups allow you to group related targets together:

```json
"target_groups": [
  {
    "id": "dns-servers",
    "name": "DNS Servers",
    "description": "Critical DNS infrastructure monitoring",
    "targets": ["cloudflare-dns", "google-dns"],
    "aggregate_reporting": true,
    "aggregate_thresholds": {
      "min_available_targets": 1,
      "critical_if_below": true
    }
  }
]
```

| Setting | Type | Description |
|---------|------|-------------|
| `id` | String | Unique identifier for this group |
| `name` | String | Human-readable name |
| `description` | String | Detailed description of this group |
| `targets` | Array | Array of target IDs in this group |
| `aggregate_reporting` | Boolean | Generate aggregate reports for the group |
| `aggregate_thresholds.min_available_targets` | Number | Minimum acceptable targets that must be UP |
| `aggregate_thresholds.critical_if_below` | Boolean | Trigger critical alert if below minimum |

## Command-Line Overrides

Many configuration options can be overridden from the command line:

```bash
./bin/netmon --debug --config custom-config.json --targets custom-targets.json
```

| Option | Description |
|--------|-------------|
| `-d, --debug` | Enable debug mode regardless of configuration |
| `-c, --config FILENAME` | Use alternative config file |
| `-t, --targets FILENAME` | Use alternative targets file |
| `-q, --quiet` | Suppress non-critical output |
| `--validate` | Validate configuration without starting monitor |
| `--slack-test` | Test Slack integration and exit |

## Environment Variables

The following environment variables can also override configuration:

| Variable | Description |
|----------|-------------|
| `NETMON_DEBUG` | Set to "true" to enable debug mode |
| `NETMON_CONFIG_FILE` | Override the config file path |
| `NETMON_TARGETS_FILE` | Override the targets file path |
| `NETMON_LOG_LEVEL` | Override the log level |
| `NETMON_SLACK_WEBHOOK` | Override the Slack webhook URL |