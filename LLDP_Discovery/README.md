# LLDP Network Discovery and Visualization Tool

A comprehensive Python-based utility to discover and visualize network topology across multi-vendor switch environments including Mikrotik, Aruba, and Arista switches using LLDP (Link Layer Discovery Protocol).

**Copyright (c) 2025 Darren Soothill**

## Directory Structure

```
LLDP_Discovery/
├── lldp_network_discovery.py  # Main discovery script
├── lldp_visualize.py          # Visualization tool
├── run_lldp_discovery.sh      # Convenience wrapper script
├── switches_config.yaml       # Example configuration
├── requirements_lldp.txt      # Python dependencies
├── README.md                  # Quick start guide (this file)
└── README_LLDP.md            # Complete documentation
```

## Quick Start

### 1. Install Dependencies

```bash
cd LLDP_Discovery
pip install -r requirements_lldp.txt
```

### 2. Configure Your Switches

Edit `switches_config.yaml` with your switch details:

```yaml
default_username: admin
default_password: yourpassword

switches:
  - hostname: 192.168.1.10
    vendor: mikrotik

  - hostname: 192.168.1.20
    vendor: aruba

  - hostname: 192.168.1.30
    vendor: arista
```

### 3. Run Discovery

**Easy way** (using the wrapper script):
```bash
./run_lldp_discovery.sh switches_config.yaml
```

**Manual way**:
```bash
# Discover network
./lldp_network_discovery.py -c switches_config.yaml -o topology.json

# Generate visualization
./lldp_visualize.py -i topology.json -o network_map.png --text-report
```

### 4. View Results

The tool generates:
- **network_topology.png** - Visual network diagram
- **network_topology.json** - Raw topology data
- **network_topology.txt** - Text-based report
- **network_topology.dot** - GraphViz file for custom visualization

## Features

- Multi-vendor support (Mikrotik, Aruba, Arista)
- Automated LLDP-based discovery
- Visual topology maps with port labels
- Color-coded by vendor
- Multiple layout algorithms
- JSON, PNG, text, and GraphViz outputs

## Supported Vendors

- **Mikrotik** - RouterOS switches/routers
- **Aruba** - ArubaOS switches (Procurve/CX)
- **Arista** - Arista EOS switches

## Requirements

- Python 3.7+
- SSH access to all switches
- LLDP enabled on all switches

## Full Documentation

See [README_LLDP.md](README_LLDP.md) for complete documentation including:
- Detailed installation instructions
- Configuration options
- LLDP setup for each vendor
- Troubleshooting guide
- Advanced usage examples
- How to extend for new vendors

## Example Output

The visualization shows:
- Devices as colored boxes (Pink=Mikrotik, Orange=Aruba, Blue=Arista)
- Connections between devices with port labels
- Network statistics (device count, connection count)
- Vendor legend

## License

Free to use and modify for your needs.
