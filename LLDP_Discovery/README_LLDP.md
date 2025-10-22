# LLDP Network Discovery and Visualization Tool

A comprehensive Python-based utility to discover and visualize network topology across multi-vendor switch environments including Mikrotik, Aruba, and Arista switches using LLDP (Link Layer Discovery Protocol).

**Copyright (c) 2025 Darren Soothill**

## Features

- **Multi-vendor Support**: Works with Mikrotik, Aruba, and Arista switches
- **Automated Discovery**: Connects to switches via SSH and retrieves LLDP neighbor information
- **Visual Network Maps**: Generates graphical topology diagrams
- **Multiple Output Formats**: PNG images, text reports, and GraphViz DOT files
- **Flexible Configuration**: YAML-based configuration for easy management
- **Port-level Detail**: Shows which ports connect to which devices

## Requirements

### Python Dependencies

```bash
pip install paramiko pyyaml networkx matplotlib
```

### System Requirements

- Python 3.7 or higher
- SSH access to all switches
- LLDP enabled on all switches

## Installation

1. Clone or download the scripts to your system
2. Install required Python packages:

```bash
pip install paramiko pyyaml networkx matplotlib
```

3. Make scripts executable:

```bash
chmod +x lldp_network_discovery.py lldp_visualize.py
```

## Configuration

### Edit `switches_config.yaml`

Create or modify the configuration file with your switch details:

```yaml
# Default credentials
default_username: admin
default_password: yourpassword

# List of switches
switches:
  - hostname: 192.168.1.10
    vendor: mikrotik

  - hostname: 192.168.1.20
    vendor: aruba
    username: admin  # Override default
    password: aruba123

  - hostname: 192.168.1.30
    vendor: arista
```

### Supported Vendors

- **mikrotik**: RouterOS switches/routers with LLDP enabled
- **aruba**: ArubaOS switches (Procurve/CX)
- **arista**: Arista EOS switches

## Usage

### Step 1: Discover Network Topology

Run the discovery script to connect to all switches and gather LLDP data:

```bash
./lldp_network_discovery.py -c switches_config.yaml -o topology.json
```

Options:
- `-c, --config`: Configuration file (required)
- `-o, --output`: Output JSON file (default: network_topology.json)
- `-v, --verbose`: Enable verbose logging

### Step 2: Generate Visual Topology Map

Create a graphical representation of your network:

```bash
./lldp_visualize.py -i topology.json -o network_map.png
```

Options:
- `-i, --input`: Input topology JSON file (required)
- `-o, --output`: Output image file (default: network_topology.png)
- `-l, --layout`: Graph layout algorithm (spring, circular, kamada_kawai, shell)
- `--no-ports`: Hide port labels on connections
- `--text-report`: Generate a text-based topology report
- `--dot-file`: Generate GraphViz DOT file for advanced visualization

### Layout Options

Different layout algorithms provide different visualization styles:

- **spring** (default): Force-directed layout, good for most topologies
- **circular**: Devices arranged in a circle
- **kamada_kawai**: Energy-based layout, good for dense networks
- **shell**: Concentric circles layout

Example with different layout:

```bash
./lldp_visualize.py -i topology.json -o network_map.png -l circular
```

### Generate Additional Reports

Generate text report and GraphViz file:

```bash
./lldp_visualize.py -i topology.json -o network_map.png --text-report --dot-file
```

This creates:
- `network_map.png` - Visual topology diagram
- `network_map.txt` - Text-based report
- `network_map.dot` - GraphViz DOT file

## Output Files

### JSON Topology File

Contains discovered network data:

```json
{
  "devices": {
    "Switch-01": {
      "hostname": "192.168.1.10",
      "vendor": "mikrotik",
      "ip": "192.168.1.10"
    }
  },
  "connections": {
    "Switch-01": [
      {
        "local_device": "Switch-01",
        "local_port": "ether1",
        "remote_device": "Switch-02",
        "remote_port": "GigabitEthernet1/0/1",
        "remote_ip": "192.168.1.20"
      }
    ]
  }
}
```

### Visual Network Map

PNG image showing:
- Devices as colored boxes (color-coded by vendor)
- Connections with port labels
- Network statistics
- Vendor legend

### Text Report

Human-readable topology report listing all devices and their connections.

### GraphViz DOT File

Can be used with GraphViz tools for custom visualizations:

```bash
dot -Tpng network_map.dot -o custom_map.png
neato -Tsvg network_map.dot -o network_map.svg
```

## Quick Start Example

```bash
# 1. Edit configuration
nano switches_config.yaml

# 2. Discover network
./lldp_network_discovery.py -c switches_config.yaml -o my_network.json

# 3. Visualize with all outputs
./lldp_visualize.py -i my_network.json -o my_network.png --text-report --dot-file
```

## Enabling LLDP on Switches

### Mikrotik RouterOS

```
/ip neighbor discovery-settings set discover-interface-list=all
```

### Aruba Switches

LLDP is typically enabled by default. To verify:

```
show lldp config
```

To enable:

```
lldp run
```

### Arista EOS

LLDP is typically enabled by default. To verify:

```
show lldp
```

To enable:

```
configure
lldp run
```

## Troubleshooting

### Connection Issues

- Verify SSH access to switches manually
- Check firewall rules
- Ensure correct credentials in config file
- Verify switches are reachable (ping test)

### LLDP Data Not Found

- Confirm LLDP is enabled on switches
- Check that neighbors are LLDP-capable
- Wait a few minutes for LLDP to exchange information
- Verify with manual LLDP commands on switches

### Parsing Errors

- Check switch OS versions (parsers may need adjustment)
- Run with `-v` flag for verbose output
- Check log messages for specific parsing issues

### Visualization Issues

- Ensure matplotlib is properly installed
- Try different layout algorithms
- For large networks, increase figure size in code
- Use `--no-ports` if labels are crowded

## Advanced Usage

### Scheduling Automatic Discovery

Create a cron job to run discovery periodically:

```bash
# Run discovery daily at 2 AM
0 2 * * * /path/to/lldp_network_discovery.py -c /path/to/switches_config.yaml -o /path/to/topology.json
```

### Integrating with Monitoring Systems

The JSON output can be consumed by other tools or scripts for:
- Network change detection
- Topology validation
- Documentation generation
- Integration with NMS/monitoring systems

### Custom Visualization

Modify `lldp_visualize.py` to customize:
- Colors for different vendors
- Node sizes and shapes
- Edge styles
- Layout parameters
- Additional metadata display

## Security Considerations

- Store credentials securely (consider using environment variables or secret management)
- Use read-only accounts where possible
- Restrict access to configuration files (`chmod 600 switches_config.yaml`)
- Consider using SSH keys instead of passwords (requires code modification)
- Run on secure, trusted networks only

## Extending the Tool

### Adding New Vendors

To add support for additional switch vendors:

1. Create a new class inheriting from `SwitchConnection` in `lldp_network_discovery.py`
2. Implement `get_hostname()` and `get_lldp_neighbors()` methods
3. Add parsing logic for that vendor's LLDP output format
4. Register the vendor in the `switch_classes` dictionary

Example:

```python
class CiscoSwitch(SwitchConnection):
    def get_hostname(self):
        # Implementation
        pass

    def get_lldp_neighbors(self):
        # Implementation
        pass
```

## License

Free to use and modify for your needs.

## Contributing

Feel free to submit improvements, bug fixes, or additional vendor support.

## Support

For issues or questions, refer to the troubleshooting section or check vendor documentation for LLDP-specific commands.
