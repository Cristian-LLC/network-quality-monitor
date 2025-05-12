# Configuration Enhancements

This document describes the advanced configuration capabilities recently added to the Network Quality Monitor.

## Configuration Validation

The system now includes strict validation of all configuration values to ensure they are within expected ranges and formats.

### Features

- **Type Validation**: Ensures configuration values are of the correct type (numeric, string, boolean)
- **Range Checking**: Verifies numeric values are within acceptable ranges
- **Required Field Checking**: Identifies missing required configuration values
- **Format Validation**: Validates URLs, webhook formats, and other structured values
- **Dependency Checking**: Ensures related configuration values are consistent

### Usage

Configuration validation happens automatically when the monitor starts, but you can also explicitly validate your configuration without starting the monitor:

```bash
./bin/netmon --validate
```

This will check all configuration files and report any errors or warnings.

## Environment Variable Overrides

Configuration values can now be overridden using environment variables, making it easier to use the tool in CI/CD pipelines, containers, or other automated environments.

### Available Overrides

| Environment Variable | Description |
|---------------------|-------------|
| `NETMON_DEBUG` | Override debug mode (`true` or `false`) |
| `NETMON_CONFIG_FILE` | Override path to config file |
| `NETMON_TARGETS_FILE` | Override path to targets file |
| `NETMON_CONNECTIVITY_CHECK_ENABLED` | Enable/disable connectivity checking |
| `NETMON_CONNECTIVITY_CHECK_INTERVAL` | Set connectivity check interval in seconds |
| `NETMON_GRACE_PERIOD_SECONDS` | Set grace period after connectivity restoration |
| `NETMON_NOTIFICATION_QUEUE_ENABLED` | Enable/disable alert queueing |
| `NETMON_SLACK_ENABLED` | Enable/disable Slack notifications |
| `NETMON_SLACK_WEBHOOK_URL` | Override Slack webhook URL |

### Usage

You can set these variables before running the monitor:

```bash
# Set debug mode on and use a different config file
NETMON_DEBUG=true NETMON_CONFIG_FILE=/path/to/custom/config.json ./bin/netmon
```

Or in a more structured environment (like Docker):

```bash
docker run -e NETMON_DEBUG=true -e NETMON_SLACK_WEBHOOK_URL=https://hooks.slack.com/... netmon-image
```

## Hot Reload of Configuration

The monitor now supports hot reloading of configuration files, allowing you to change settings without restarting the monitoring process.

### Features

- **File Watching**: Detects changes to configuration files automatically
- **Validation Before Reload**: Ensures new configuration is valid before applying
- **Signal-Based Reload**: Supports manual reload via SIGHUP signal
- **Zero Downtime**: Continues monitoring during reload
- **Change Reporting**: Reports configuration changes that were applied

### Usage

#### Automatic Reload

The monitor automatically checks for changes to configuration files every 5 seconds. When changes are detected:

1. The new configuration is loaded and validated
2. If valid, the changes are applied immediately
3. A message is displayed showing what settings changed
4. If invalid, the old configuration remains in effect

#### Manual Reload

You can also trigger a reload manually by sending a SIGHUP signal to the monitor:

```bash
# Find the PID of the main monitor process
ps aux | grep netmon

# Send SIGHUP signal
kill -SIGHUP <pid>
```

### Reload Behavior

When configuration is reloaded:

- Settings that don't require restart take effect immediately
- The system maintains all existing connections and monitoring statistics
- No alerts or reports are lost during the reload
- Notifications settings are updated in real-time

## Best Practices

- **Always Validate**: Use `--validate` before deploying configuration changes to production
- **Use Environment Variables**: For sensitive information like webhook URLs
- **Hot Reload**: Make small, incremental changes when using hot reload
- **Backup Configs**: Always keep a backup of working configuration files
- **Monitor Logs**: Watch for validation warnings and errors after making changes