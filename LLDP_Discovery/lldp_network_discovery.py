#!/usr/bin/env python3
"""
LLDP Network Discovery and Visualization Tool
Supports Mikrotik, Aruba, and Arista switches

Copyright (c) 2025 Darren Soothill
"""

import paramiko
import json
import yaml
import re
import argparse
import logging
from typing import Dict, List, Tuple, Optional
from collections import defaultdict
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SwitchConnection:
    """Base class for switch connections"""

    def __init__(self, hostname: str, username: str, password: str, port: int = 22):
        self.hostname = hostname
        self.username = username
        self.password = password
        self.port = port
        self.client = None
        self.shell = None

    def connect(self) -> bool:
        """Establish SSH connection to the switch"""
        try:
            self.client = paramiko.SSHClient()
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.client.connect(
                self.hostname,
                port=self.port,
                username=self.username,
                password=self.password,
                timeout=10,
                look_for_keys=False,
                allow_agent=False
            )
            logger.info(f"Connected to {self.hostname}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to {self.hostname}: {str(e)}")
            return False

    def disconnect(self):
        """Close SSH connection"""
        if self.client:
            self.client.close()
            logger.info(f"Disconnected from {self.hostname}")

    def execute_command(self, command: str, timeout: int = 30) -> str:
        """Execute command and return output"""
        try:
            stdin, stdout, stderr = self.client.exec_command(command, timeout=timeout)
            output = stdout.read().decode('utf-8')
            error = stderr.read().decode('utf-8')
            if error:
                logger.warning(f"Command stderr on {self.hostname}: {error}")
            return output
        except Exception as e:
            logger.error(f"Failed to execute command on {self.hostname}: {str(e)}")
            return ""


class MikrotikSwitch(SwitchConnection):
    """Mikrotik-specific switch handler"""

    def get_hostname(self) -> str:
        """Get switch hostname"""
        output = self.execute_command("/system identity print")
        match = re.search(r'name:\s*(\S+)', output)
        return match.group(1) if match else self.hostname

    def get_lldp_neighbors(self) -> List[Dict]:
        """Get LLDP neighbor information"""
        output = self.execute_command("/ip neighbor print detail")
        neighbors = []

        # Parse Mikrotik LLDP output
        current_neighbor = {}
        for line in output.split('\n'):
            line = line.strip()
            if not line or line.startswith('Flags:'):
                continue

            if re.match(r'^\d+', line):
                if current_neighbor:
                    neighbors.append(current_neighbor)
                current_neighbor = {}

            # Parse key-value pairs
            if '=' in line:
                parts = line.split('=', 1)
                key = parts[0].strip()
                value = parts[1].strip() if len(parts) > 1 else ''

                if 'interface' in key.lower():
                    current_neighbor['local_port'] = value
                elif 'identity' in key.lower() or 'system-name' in key.lower():
                    current_neighbor['remote_device'] = value
                elif 'interface-name' in key.lower():
                    current_neighbor['remote_port'] = value
                elif 'address' in key.lower():
                    current_neighbor['remote_ip'] = value

        if current_neighbor:
            neighbors.append(current_neighbor)

        return neighbors


class ArubaSwitch(SwitchConnection):
    """Aruba-specific switch handler"""

    def get_hostname(self) -> str:
        """Get switch hostname"""
        output = self.execute_command("show running-config | include hostname")
        match = re.search(r'hostname\s+"?([^"\s]+)"?', output)
        return match.group(1) if match else self.hostname

    def get_lldp_neighbors(self) -> List[Dict]:
        """Get LLDP neighbor information"""
        output = self.execute_command("show lldp neighbors-information detail")
        neighbors = []

        current_neighbor = {}
        for line in output.split('\n'):
            line = line.strip()

            # Local port
            match = re.search(r'Local Port\s*:\s*(\S+)', line)
            if match:
                if current_neighbor:
                    neighbors.append(current_neighbor)
                current_neighbor = {'local_port': match.group(1)}

            # Remote system name
            match = re.search(r'System Name\s*:\s*(.+)', line)
            if match:
                current_neighbor['remote_device'] = match.group(1).strip()

            # Remote port
            match = re.search(r'Port ID\s*:\s*(.+)', line)
            if match:
                current_neighbor['remote_port'] = match.group(1).strip()

            # Remote IP
            match = re.search(r'Management Address\s*:\s*(\S+)', line)
            if match:
                current_neighbor['remote_ip'] = match.group(1)

        if current_neighbor:
            neighbors.append(current_neighbor)

        return neighbors


class AristaSwitch(SwitchConnection):
    """Arista-specific switch handler"""

    def get_hostname(self) -> str:
        """Get switch hostname"""
        output = self.execute_command("show hostname")
        lines = output.strip().split('\n')
        for line in lines:
            line = line.strip()
            if line and not line.startswith('Hostname:') and not line.startswith('FQDN:'):
                return line
            match = re.search(r'Hostname:\s*(\S+)', line)
            if match:
                return match.group(1)
        return self.hostname

    def get_lldp_neighbors(self) -> List[Dict]:
        """Get LLDP neighbor information"""
        output = self.execute_command("show lldp neighbors detail")
        neighbors = []

        current_neighbor = {}
        for line in output.split('\n'):
            line = line.strip()

            # Interface line
            match = re.search(r'Interface\s+(\S+)\s+detected', line)
            if match:
                if current_neighbor:
                    neighbors.append(current_neighbor)
                current_neighbor = {'local_port': match.group(1)}

            # Remote system name
            match = re.search(r'System Name:\s*"?([^"\n]+)"?', line)
            if match:
                current_neighbor['remote_device'] = match.group(1).strip()

            # Remote port
            match = re.search(r'Port ID\s*:\s*"?([^"\n]+)"?', line)
            if match:
                current_neighbor['remote_port'] = match.group(1).strip()

            # Remote IP
            match = re.search(r'Management Address\s*:\s*(\S+)', line)
            if match:
                current_neighbor['remote_ip'] = match.group(1)

        if current_neighbor:
            neighbors.append(current_neighbor)

        return neighbors


class NetworkDiscovery:
    """Main network discovery coordinator"""

    def __init__(self, config_file: str):
        self.config = self.load_config(config_file)
        self.topology = defaultdict(list)
        self.devices = {}
        self.switch_classes = {
            'mikrotik': MikrotikSwitch,
            'aruba': ArubaSwitch,
            'arista': AristaSwitch
        }

    def load_config(self, config_file: str) -> Dict:
        """Load configuration from YAML file"""
        try:
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            logger.info(f"Loaded configuration from {config_file}")
            return config
        except Exception as e:
            logger.error(f"Failed to load config: {str(e)}")
            raise

    def discover_network(self):
        """Discover the entire network topology"""
        switches = self.config.get('switches', [])

        for switch_config in switches:
            hostname = switch_config['hostname']
            vendor = switch_config['vendor'].lower()
            username = switch_config.get('username', self.config.get('default_username'))
            password = switch_config.get('password', self.config.get('default_password'))

            logger.info(f"Discovering {hostname} ({vendor})")

            if vendor not in self.switch_classes:
                logger.warning(f"Unsupported vendor: {vendor}")
                continue

            switch_class = self.switch_classes[vendor]
            switch = switch_class(hostname, username, password)

            if not switch.connect():
                continue

            try:
                device_name = switch.get_hostname()
                neighbors = switch.get_lldp_neighbors()

                self.devices[device_name] = {
                    'hostname': hostname,
                    'vendor': vendor,
                    'ip': hostname
                }

                for neighbor in neighbors:
                    if all(k in neighbor for k in ['local_port', 'remote_device', 'remote_port']):
                        connection = {
                            'local_device': device_name,
                            'local_port': neighbor['local_port'],
                            'remote_device': neighbor['remote_device'],
                            'remote_port': neighbor['remote_port'],
                            'remote_ip': neighbor.get('remote_ip', 'N/A')
                        }
                        self.topology[device_name].append(connection)
                        logger.info(f"  {device_name}:{neighbor['local_port']} -> "
                                  f"{neighbor['remote_device']}:{neighbor['remote_port']}")

            finally:
                switch.disconnect()

    def export_to_json(self, filename: str):
        """Export topology to JSON file"""
        output = {
            'devices': self.devices,
            'connections': dict(self.topology)
        }
        with open(filename, 'w') as f:
            json.dump(output, f, indent=2)
        logger.info(f"Topology exported to {filename}")

    def get_topology_data(self) -> Tuple[Dict, Dict]:
        """Return topology data for visualization"""
        return self.devices, dict(self.topology)


def main():
    parser = argparse.ArgumentParser(description='LLDP Network Discovery Tool')
    parser.add_argument('-c', '--config', required=True, help='Configuration file (YAML)')
    parser.add_argument('-o', '--output', default='network_topology.json',
                       help='Output JSON file')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Verbose logging')

    args = parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    discovery = NetworkDiscovery(args.config)
    discovery.discover_network()
    discovery.export_to_json(args.output)

    logger.info("Discovery complete!")


if __name__ == '__main__':
    main()
