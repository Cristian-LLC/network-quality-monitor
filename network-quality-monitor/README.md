# Network Quality Monitor

A professional, enterprise-grade bash-based network monitoring tool that provides real-time statistics for network quality assessment. It uses `fping` in loop mode to continuously monitor network connections and calculates various metrics for comprehensive network evaluation.

## Features

- **Real-time Network Analysis**
  - Configurable ping frequency for continuous monitoring
  - Comprehensive statistics collection including RTT, jitter, and packet loss
  - ITU-T G.107 E-model implementation for voice quality metrics (R-factor & MOS)
  - TTL monitoring for detecting routing changes

- **Advanced Configuration System**
  - Strict validation of all configuration parameters
  - Environment variable overrides for automated deployment
  - Hot-reload of configuration without service restart
  - Centralized configuration with detailed options

- **Intelligent Alerting System**
  - Configurable thresholds for connection loss and packet degradation
  - Alert suppression during connectivity outages to prevent alert storms
  - Smart recovery detection with configurable grace periods
  - Offline alert queueing with automatic delivery when connectivity returns

- **Enterprise-ready Monitoring**
  - Target-specific monitoring configuration
  - Logical target grouping with aggregate statistics
  - Prioritization system for critical infrastructure
  - Color-coded console output for visual assessment

- **Multi-channel Notifications**
  - Slack integration with customizable messages and channels
  - Email integration with configurable recipients
  - Webhook support for third-party integrations
  - Alert queuing with automatic delivery

- **Professional Design**
  - Modular architecture for maintainability and extensibility
  - Clean process management with proper signal handling
  - Cross-platform compatibility (Linux, macOS)
  - Comprehensive logging and error handling

## Project Structure

```
network-quality-monitor/
├── src/                    # Source code
│   ├── core/               # Core functionality
│   ├── utils/              # Utility functions
│   └── notifications/      # Notification system
├── config/                 # Configuration files
├── bin/                    # Executable scripts
├── tests/                  # Test scripts
├── tools/                  # Utility scripts
├── logs/                   # Log files
└── docs/                   # Documentation
```

## Requirements

- Bash shell (version 3.2+ supported, 4.0+ recommended)
- fping (for network probing and monitoring)
- jq (for JSON configuration processing)
- bc (for mathematical calculations)

## Quick Start

1. Install dependencies:
   ```bash
   # On macOS
   brew install fping jq bc

   # On Linux (Debian/Ubuntu)
   sudo apt install fping jq bc
   ```

2. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/network-quality-monitor.git
   cd network-quality-monitor
   ```

3. Run the setup script:
   ```bash
   ./tools/setup.sh
   ```

4. Start monitoring:
   ```bash
   ./bin/netmon
   ```

## Documentation

- **[Installation Guide](docs/installation.md)** - Detailed installation instructions
- **[Configuration Guide](docs/configuration.md)** - Basic configuration instructions
- **[Advanced Configuration](docs/advanced-configuration.md)** - Detailed configuration options
- **[Configuration Enhancements](docs/configuration-enhancements.md)** - Advanced configuration features
- **[Metrics Explained](docs/metrics.md)** - Understanding the monitored metrics

## Configuration

Network Quality Monitor uses two main configuration files:

- **`config/config.json`** - Global settings and integration configuration
- **`config/targets.json`** - Target-specific monitoring configuration

Example configuration:

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

## Usage

```bash
./bin/netmon [options]
```

### Options

- `-h, --help`: Show help information
- `-c, --config FILENAME`: Specify a different config file
- `-t, --targets FILENAME`: Specify a different targets file
- `-d, --debug`: Show additional debug information
- `-v, --version`: Show program version
- `-q, --quiet`: Suppress all non-critical output
- `--slack-test`: Test Slack integration and exit
- `--validate`: Validate configuration files and exit

You can also use environment variables to override configuration options:

```bash
# Example of using environment variables
NETMON_DEBUG=true NETMON_GRACE_PERIOD_SECONDS=60 ./bin/netmon
```

See [Configuration Enhancements](docs/configuration-enhancements.md) for details.

## License

MIT License

Copyright © 2025 Cristian O.