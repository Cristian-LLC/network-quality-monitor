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