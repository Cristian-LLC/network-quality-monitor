# Installation Guide for Network Quality Monitor

This guide will help you install and set up the Network Quality Monitor on your system.

## Prerequisites

Before installing, make sure you have the following prerequisites:

- Bash shell (version 3.2+ supported, 4.0+ recommended for better performance)
- Administrative privileges (for installing dependencies)

## Step 1: Install Dependencies

### macOS

macOS comes with an older version of Bash (3.2) due to licensing issues. The script is compatible with this version, but you'll need to install the required dependencies:

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required dependencies
brew install fping jq bc

# Install optional dependencies for enhanced connectivity detection
brew install curl bind # bind provides dig and host commands

# Optional: Install a newer version of Bash (recommended but not required)
brew install bash
# Add the new shell to allowed shells
sudo bash -c 'echo /usr/local/bin/bash >> /etc/shells'
# Change your shell (optional)
chsh -s /usr/local/bin/bash
```

### Linux (Debian/Ubuntu)

```bash
# Install required dependencies
sudo apt update
sudo apt install fping jq bc

# Install optional dependencies for enhanced connectivity detection
sudo apt install curl dnsutils # dnsutils provides dig, host and nslookup
```

### Linux (RHEL/CentOS/Fedora)

```bash
# Install required dependencies
sudo yum install epel-release
sudo yum install fping jq bc

# Install optional dependencies for enhanced connectivity detection
sudo yum install curl bind-utils # bind-utils provides dig, host and nslookup
```

## Step 2: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/yourusername/network-quality-monitor.git
cd network-quality-monitor
```

## Step 3: Set Up Configuration

1. Copy the example configuration files:

```bash
cp config/targets.json.example config/targets.json
cp config/notifications.json.example config/notifications.json
```

2. Edit the configuration files to match your requirements:

```bash
# Edit targets configuration
nano config/targets.json

# Edit notification settings (optional)
nano config/notifications.json
```

## Step 4: Make Scripts Executable

```bash
# Make the main script executable
chmod +x bin/netmon

# Make all component scripts executable
find src -name "*.sh" -exec chmod +x {} \;
find tests -name "*.sh" -exec chmod +x {} \;
find tools -name "*.sh" -exec chmod +x {} \;
```

## Step 5: Run the Setup Script (Optional)

The setup script performs additional configuration and validation:

```bash
./tools/setup.sh
```

## Step 6: Create a Symlink (Optional)

For easier access, you can create a symlink to the main script in a directory that's in your PATH:

```bash
# For system-wide access (requires sudo)
sudo ln -s "$(pwd)/bin/netmon" /usr/local/bin/netmon

# OR for user-only access
mkdir -p ~/.local/bin
ln -s "$(pwd)/bin/netmon" ~/.local/bin/netmon
# Make sure ~/.local/bin is in your PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Running the Monitor

Now you can run the Network Quality Monitor using:

```bash
# Using the executable directly
./bin/netmon

# OR using the symlink (if created)
netmon

# Show debug information
netmon --debug

# Use a different configuration file
netmon --file /path/to/custom/config.json
```

## Troubleshooting

If you encounter issues during installation or execution, please check the following:

1. Ensure all dependencies are correctly installed
2. Verify file permissions (scripts should be executable)
3. Check configuration file syntax (must be valid JSON)
4. Review log files in the logs directory

For additional help or to report bugs, please open an issue on the GitHub repository.