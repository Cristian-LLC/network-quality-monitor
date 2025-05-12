# Configuration Guide for Network Quality Monitor

This document explains how to configure the Network Quality Monitor for your specific network monitoring needs.

## Configuration Files

Network Quality Monitor uses JSON configuration files located in the `config/` directory:

- `targets.json`: Defines what hosts to monitor and their monitoring parameters
- `notifications.json`: Configures notification settings (Slack, etc.)

## Target Configuration (targets.json)

The `targets.json` file has two main sections:

1. `config`: Global configuration settings
2. `targets`: Array of hosts to monitor

### Example Configuration

```json
{
  "config": {
    "connectivity_check": {
      "enabled": true,
      "check_interval": 1,
      "servers": ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
    }
  },
  "targets": [
    {
      "ip": "1.1.1.1",
      "ping_frequency": 1,
      "consecutive_loss_threshold": 2,
      "loss_threshold_pct": 10,
      "report_interval": 10
    },
    {
      "ip": "8.8.8.8",
      "ping_frequency": 1,
      "consecutive_loss_threshold": 3,
      "loss_threshold_pct": 5,
      "report_interval": 15
    },
    {
      "ip": "google.com",
      "ping_frequency": 1,
      "consecutive_loss_threshold": 2,
      "loss_threshold_pct": 5,
      "report_interval": 10
    }
  ]
}
```

### Global Configuration Fields

| Field | Type | Description | Example |
|---|---|---|---|
| `config.connectivity_check.enabled` | Boolean | Enable or disable local connectivity checking | `true` |
| `config.connectivity_check.check_interval` | Number | How often to check local connectivity, in seconds | `1` for checking every second |
| `config.connectivity_check.servers` | Array | List of servers to check for connectivity | `["1.1.1.1", "8.8.8.8", "9.9.9.9"]` |

### Target Configuration Fields

Each target in the `targets` array has the following fields:

| Field | Type | Description | Example |
|---|---|---|---|
| `ip` | String | The IP address or hostname to monitor. Can be any valid IP address or domain name. | `"1.1.1.1"`, `"google.com"` |
| `ping_frequency` | Number | How often to send ping packets, in seconds. Lower values give more granular data but increase network traffic. | `1` for one ping per second |
| `consecutive_loss_threshold` | Number | How many ping packets must be lost in a row before declaring a host DOWN. Higher values prevent false alarms due to transient packet loss. | `2` means DOWN after 2 consecutive lost pings |
| `loss_threshold_pct` | Number | The percentage of packet loss that triggers a LOSS ALERT. This is calculated over the report interval. | `10` means alert when 10% or more packets are lost |
| `report_interval` | Number | How often to generate a status report, in seconds. This also determines the window for calculating packet loss percentage. | `10` for a report every 10 seconds |

## Notification Configuration (notifications.json)

The `notifications.json` file configures how notifications are sent when alerts occur.

### Example Slack Configuration

```json
{
  "slack": {
    "enabled": true,
    "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
    "default_channel": "#network-alerts",
    "notifications": {
      "host_down": {
        "channel": "#network-alerts"
      },
      "loss_alert": {
        "channel": "#network-warnings"
      },
      "recovery": {
        "channel": "#network-alerts"
      }
    }
  }
}
```

### Slack Configuration Fields

| Field | Type | Required | Description | Example |
|---|---|---|---|---|
| `slack.enabled` | Boolean | Yes | Master switch to enable or disable all Slack notifications. Set to `false` during initial setup or to temporarily disable notifications. | `true` |
| `slack.webhook_url` | String | Yes | The Slack webhook URL for your workspace. You can create this in Slack's Incoming Webhooks app settings. Must be the complete URL. | `"https://hooks.slack.com/services/T00000/B00000/XXXXXXX"` |
| `slack.default_channel` | String | No | The default Slack channel to use if a specific notification type doesn't have a channel specified. Must include the `#` prefix. | `"#network-alerts"` |
| `slack.notifications.host_down.channel` | String | No | The channel where "host down" notifications will be sent. Overrides the default channel for this specific notification type. | `"#critical-alerts"` |
| `slack.notifications.loss_alert.channel` | String | No | The channel where packet loss notifications will be sent. | `"#network-warnings"` |
| `slack.notifications.recovery.channel` | String | No | The channel where recovery notifications will be sent when a host comes back up. | `"#network-alerts"` |

## Configuration Tips

### Target Configuration

- For mission-critical services, use lower `consecutive_loss_threshold` values (1-2)
- For less critical services or unstable networks, use higher threshold values (3-5) to reduce alert noise
- Adjust `report_interval` based on your monitoring needs:
  - Shorter intervals (5-10s) for real-time monitoring
  - Longer intervals (30-60s) for long-term trend analysis with less output
- The `ping_frequency` of 1 second is suitable for most use cases, but can be increased for less important targets

### Connectivity Checking

- Lower `check_interval` values (1-5s) provide faster response to connectivity changes but increase CPU usage
- Use multiple diverse servers in the `servers` array for reliable connectivity detection
- Include both public DNS servers (e.g., 1.1.1.1, 8.8.8.8) and major website IPs for best results

### Slack Notifications

- Create dedicated channels for different alert types to avoid notification fatigue
- Use descriptive channel names that match the severity of alerts
- Consider setting up a notification schedule to avoid alerts during maintenance windows