# Network Quality Monitor

A powerful bash-based network monitoring tool that provides real-time statistics for network quality assessment. It uses `fping` in loop mode to continuously monitor network connections and calculates various metrics for comprehensive network evaluation.

## Features

- Real-time network monitoring with customizable ping frequency
- Comprehensive statistics:
  - RTT (Round Trip Time) with min/avg/max values
  - Jitter calculation using RFC 3550 method
  - TTL (Time To Live) monitoring
  - ITU-T G.107 E-model implementation for R-factor calculation
  - MOS (Mean Opinion Score) display
  - Packet loss detection and percentage calculation
- Color-coded metrics for easy visual assessment
- Configurable alert thresholds for connection loss and packet loss
- Multiple target monitoring with individual configurations
- Clean process management with proper signal handling
- Modular notification system:
  - Slack integration with configurable channels and throttling
  - Event-based notifications (host down, recovery, loss alerts)
  - Extensible architecture for additional notification methods

## Requirements

- Bash shell (version 3.2+ supported, 4.0+ recommended for better performance)
- fping (for network probing and monitoring)
- jq (for JSON configuration processing)
- bc (for mathematical calculations)

## Installation

### macOS

macOS comes with an older version of Bash (3.2) due to licensing issues. The script is compatible with this version, but you'll need to install the required dependencies:

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install fping jq bc

# Optional: Install a newer version of Bash (recommended but not required)
brew install bash
# Add the new shell to allowed shells
sudo bash -c 'echo /usr/local/bin/bash >> /etc/shells'
# Change your shell (optional)
chsh -s /usr/local/bin/bash
```

### Linux (Debian/Ubuntu)

```bash
# Install dependencies
sudo apt update
sudo apt install fping jq bc
```

### Linux (RHEL/CentOS/Fedora)

```bash
# Install dependencies
sudo yum install epel-release
sudo yum install fping jq bc
```

### General Setup

1. Clone this repository or download the files:
   ```bash
   git clone https://github.com/Cristian-LLC/network-quality-monitor.git
   cd network-quality-monitor
   ```

2. Make the script executable:
   ```bash
   chmod +x ping.sh
   ```

3. Configure your monitoring targets in `targets.json`

## Usage

```
./ping.sh [options]
```

### Options

- `-h, --help`: Show help information
- `-f, --file FILENAME`: Specify a different config file (default: targets.json)
- `-d, --debug`: Show additional debug information
- `-v, --version`: Show program version

### Stopping the Monitor

The monitor runs continuously until stopped. To stop it:

- Press `Ctrl+C` to terminate all monitoring processes
- The script will automatically clean up any child processes and temporary files

## Troubleshooting

### Common Issues

#### Permission Denied

If you see a "Permission denied" error:

```
-bash: ./ping.sh: Permission denied
```

Make sure the script is executable:

```bash
chmod +x ping.sh
```

#### Command Not Found: fping/jq/bc

If you see a "command not found" error:

```
./ping.sh: line XX: fping: command not found
```

Install the missing dependency as described in the Installation section.

#### Older Bash Version Warning

If you see a warning about associative arrays:

```
./ping.sh: line XX: declare: -A: invalid option
```

This is normal on macOS with Bash 3.2. The script will automatically adapt to use compatible alternatives. For best performance, consider installing a newer version of Bash as described in the macOS installation section.

### Configuration

The `targets.json` file uses the following format:

```json
[
  {
    "ip": "1.1.1.1",
    "ping_frequency": 1,
    "consecutive_loss_threshold": 2,
    "loss_threshold_pct": 10,
    "report_interval": 10
  }
]
```

#### Configuration Fields Explained

Each target in the configuration has the following fields:

| Field | Type | Description | Example |
|---|---|---|---|
| `ip` | String | The IP address or hostname to monitor. Can be any valid IP address or domain name. | `"1.1.1.1"`, `"google.com"` |
| `ping_frequency` | Number | How often to send ping packets, in seconds. Lower values give more granular data but increase network traffic. | `1` for one ping per second |
| `consecutive_loss_threshold` | Number | How many ping packets must be lost in a row before declaring a host DOWN. Higher values prevent false alarms due to transient packet loss. | `2` means DOWN after 2 consecutive lost pings |
| `loss_threshold_pct` | Number | The percentage of packet loss that triggers a LOSS ALERT. This is calculated over the report interval. | `10` means alert when 10% or more packets are lost |
| `report_interval` | Number | How often to generate a status report, in seconds. This also determines the window for calculating packet loss percentage. | `10` for a report every 10 seconds |

#### Configuration Tips

- For mission-critical services, use lower `consecutive_loss_threshold` values (1-2)
- For less critical services or unstable networks, use higher threshold values (3-5) to reduce alert noise
- Adjust `report_interval` based on your monitoring needs:
  - Shorter intervals (5-10s) for real-time monitoring
  - Longer intervals (30-60s) for long-term trend analysis with less output
- The `ping_frequency` of 1 second is suitable for most use cases, but can be increased for less important targets

## Output Metrics Explained

### RTT (Round Trip Time)
- Displayed as `MIN/AVG/MAX` in milliseconds
- Color coding:
  - Green: < 80ms (good)
  - Yellow: 80-150ms (warning)
  - Red: > 150ms (poor)

### Jitter
- Calculated using the RFC 3550 EWMA (Exponential Weighted Moving Average) method with 1/16 gain factor
- Color coding:
  - Green: < 10ms (good)
  - Yellow: 10-30ms (warning)
  - Red: > 30ms (poor)

### TTL (Time To Live)
- Shows the number of network hops before a packet would be discarded
- Color coding:
  - Green: ≥ 64 (normal)
  - Yellow: 32-63 (warning - unusual TTL)
  - Red: < 32 (potential routing issue)

### R-factor
- Based on ITU-T G.107 E-model (0-100 scale)
- Perceived voice quality bands:
  - ≥ 81: Excellent/PSTN-like (Green)
  - 71-80: Good - most users satisfied (Green)
  - 61-70: Fair - some complaints (Yellow)
  - 51-60: Poor - many users dissatisfied (Yellow)
  - < 50: Bad - nearly all users dissatisfied (Red)

### MOS (Mean Opinion Score)
- Derived from R-factor (1.0-5.0 scale)
- Perceived quality bands:
  - > 4.0: Excellent/Good (Green)
  - 3.6-4.0: Fair (Yellow)
  - 3.1-3.5: Poor (Yellow)
  - < 3.0: Bad (Red)

### Packet Loss
- Percentage of lost packets during the reporting interval
- Color coding:
  - Green: 0% (no loss)
  - Yellow: > 0% but below threshold
  - Red: ≥ threshold (configurable in targets.json)

## Alert Types

- `[DOWN]`: Triggered when consecutive packet losses exceed the configured threshold
- `[LOSS ALERT]`: Triggered when packet loss percentage exceeds the configured threshold
- `[UP]`: Displayed when a previously down connection recovers

## Technical Implementation Details

### ITU-T G.107 E-model Implementation

The script implements the ITU-T G.107 E-model to calculate the R-factor, which measures voice quality. This model considers several factors:

- **R0**: Basic signal-to-noise ratio (default: 93.2)
- **Is**: Simultaneous impairment factor (default: 1.4)
- **Id**: Delay impairment factor, calculated from one-way delay
- **Ie-eff**: Effective equipment impairment factor, which accounts for:
  - Codec impairment
  - Packet loss effects
  - Jitter effects
- **A**: Advantage factor (0 for wired connections, higher for mobile)

The R-factor is calculated as: `R = R0 - Is - Id - Ie-eff + A`

### Jitter Calculation

Jitter is calculated using the RFC 3550 EWMA (Exponential Weighted Moving Average) method with a 1/16 gain factor:

```
J(i) = J(i-1) + (|D(i-1,i)| - J(i-1))/16
```

Where:
- J(i) is the current jitter estimate
- J(i-1) is the previous jitter estimate
- |D(i-1,i)| is the absolute difference between successive RTT values

## Notification System

Network Quality Monitor includes a modular notification system that can send alerts for various network events. Currently, it supports Slack notifications.

### Slack Notifications

You can configure the script to send alerts to Slack channels when important events occur:

- **Host Down**: When a host is detected as down after consecutive lost pings
- **Loss Alert**: When packet loss exceeds the configured threshold
- **Recovery**: When a host recovers after being down

#### Configuring Slack Notifications

##### Step 1: Create a Slack App and Webhook

1. Go to [Slack API Apps page](https://api.slack.com/apps)
2. Click "Create New App" and choose "From scratch"
3. Name your app (e.g., "Network Monitor") and select your workspace
4. In the sidebar, click on "Incoming Webhooks"
5. Toggle "Activate Incoming Webhooks" to On
6. Click "Add New Webhook to Workspace"
7. Select the channel to post to by default (you can override this later)
8. Click "Allow"
9. Copy the Webhook URL shown on the page (starts with https://hooks.slack.com/services/)

##### Step 2: Configure Network Quality Monitor

1. Edit `notifications/notification_config.json`:
   ```json
   {
     "slack": {
       "enabled": true,
       "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
       "default_channel": "#network-alerts",
       "notifications": {
         "host_down": {
           "channel": "#network-alerts",
           "throttle_minutes": 5
         },
         "loss_alert": {
           "channel": "#network-warnings",
           "throttle_minutes": 15
         },
         "recovery": {
           "channel": "#network-alerts",
           "throttle_minutes": 0
         }
       }
     }
   }
   ```
2. Replace `"https://hooks.slack.com/services/YOUR/WEBHOOK/URL"` with the actual webhook URL you copied
3. Set `"enabled": true` to activate Slack notifications
4. Customize the channels for each notification type if desired

##### Step 3: Test Your Configuration

1. Run the monitoring script: `./ping.sh`
2. If you want to test notifications without waiting for actual network issues:
   - Temporarily modify a target IP to an invalid one to trigger "host down" notifications
   - Or set a very low `loss_threshold_pct` value to trigger loss alerts more easily

##### Example Notification Appearance

When a host goes down, you'll see a message in Slack that looks like:

```
Network Monitor   [satellite_antenna]

Network Alert
Host: 1.1.1.1
Host 1.1.1.1 is DOWN after 2 consecutive losses.

Network Quality Monitor • Today at 12:34 PM
```

#### Slack Configuration Reference

The `notification_config.json` file contains all settings for notification integrations. Here's a detailed explanation of each field in the Slack configuration:

| Field | Type | Required | Description | Example |
|---|---|---|---|---|
| `slack.enabled` | Boolean | Yes | Master switch to enable or disable all Slack notifications. Set to `false` during initial setup or to temporarily disable notifications. | `true` |
| `slack.webhook_url` | String | Yes | The Slack webhook URL for your workspace. You can create this in Slack's Incoming Webhooks app settings. Must be the complete URL. | `"https://hooks.slack.com/services/T00000/B00000/XXXXXXX"` |
| `slack.default_channel` | String | No | The default Slack channel to use if a specific notification type doesn't have a channel specified. Must include the `#` prefix. | `"#network-alerts"` |
| `slack.notifications.host_down.channel` | String | No | The channel where "host down" notifications will be sent. Overrides the default channel for this specific notification type. | `"#critical-alerts"` |
| `slack.notifications.host_down.throttle_minutes` | Number | No | The minimum time in minutes between repeated "host down" notifications for the same host. Prevents notification spam during persistent outages. | `5` |
| `slack.notifications.loss_alert.channel` | String | No | The channel where packet loss notifications will be sent. | `"#network-warnings"` |
| `slack.notifications.loss_alert.throttle_minutes` | Number | No | The minimum time in minutes between repeated loss alert notifications for the same host. | `15` |
| `slack.notifications.recovery.channel` | String | No | The channel where recovery notifications will be sent when a host comes back up. | `"#network-alerts"` |
| `slack.notifications.recovery.throttle_minutes` | Number | No | The minimum time in minutes between recovery notifications. Usually set to `0` since recoveries are important and infrequent. | `0` |

### Extending the Notification System

The notification system is designed to be modular and extensible. You can add support for additional notification channels (like email, SMS, Discord, etc.) by following these steps:

1. Create a new notification module in the `notifications/` directory (e.g., `notifications/discord.sh`)
2. Implement the necessary functions for your notification channel
3. Update the notification configuration in `notification_config.json`
4. The new notification module will be automatically loaded if it's properly referenced in `hooks.sh`

Example implementation structure for a new notification module:

```bash
#!/usr/bin/env bash
# notifications/discord.sh - Discord notification module

# Check if Discord integration is enabled
is_discord_enabled() {
  local enabled
  enabled=$(jq -r '.discord.enabled // false' "$NOTIFICATION_CONFIG" 2>/dev/null)

  if [ "$enabled" = "true" ]; then
    return 0
  else
    return 1
  fi
}

# Send notification to Discord
send_discord_alert() {
  local alert_type="$1"
  local ip="$2"
  local message="$3"

  # Implementation details...
}
```

Then update `hooks.sh` to load the new module:

```bash
# Load specific notification modules if they exist
if [ -f "notifications/slack.sh" ]; then
  source notifications/slack.sh
fi
if [ -f "notifications/discord.sh" ]; then
  source notifications/discord.sh
fi
```

## OS Compatibility

The Network Quality Monitor has been tested on the following operating systems:

| OS | Status | Notes |
|---|---|---|
| macOS | ✅ Fully Compatible | Tested on macOS Ventura and newer. Works with default Bash 3.2 or newer versions. |
| Ubuntu/Debian | ✅ Fully Compatible | Tested on Ubuntu 20.04 LTS and newer. |
| CentOS/RHEL | ✅ Fully Compatible | Tested on CentOS 7 and newer. |
| Fedora | ✅ Fully Compatible | Tested on Fedora 34 and newer. |
| Windows WSL | ✅ Fully Compatible | Works well under Windows Subsystem for Linux. |
| Windows Cygwin | ⚠️ Limited Compatibility | May require additional configuration. |
| FreeBSD | ⚠️ Limited Compatibility | Requires GNU-compatible tools. |

## Contributing

Contributions are welcome! Here are some ways you can contribute to this project:

1. **Bug Reports**: Create an issue if you encounter any bugs or problems
2. **Feature Requests**: Suggest new features or improvements
3. **Code Contributions**: Submit pull requests with bug fixes or new features
4. **Documentation**: Improve or correct the documentation

When contributing, please follow these steps:

1. Fork the repository
2. Create a new branch for your feature or bugfix
3. Commit your changes
4. Push to your branch
5. Create a new Pull Request

### Development Requirements

For development, you'll need:

- Git
- Bash (version 4.0+ recommended for testing all features)
- The dependencies listed in the Requirements section

## License

MIT License

Copyright © 2025 Cristian O.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.