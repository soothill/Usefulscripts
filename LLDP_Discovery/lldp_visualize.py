#!/usr/bin/env python3
"""
LLDP Network Topology Visualization Tool
Creates graphical representation of network topology

Copyright (c) 2025 Darren Soothill
"""

import json
import argparse
import logging
from typing import Dict, List
import networkx as nx
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import matplotlib.patches as mpatches

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class NetworkVisualizer:
    """Creates visual network topology graphs"""

    def __init__(self, topology_file: str):
        self.topology_file = topology_file
        self.devices = {}
        self.connections = {}
        self.graph = nx.Graph()
        self.vendor_colors = {
            'mikrotik': '#E91E63',  # Pink
            'aruba': '#FF9800',     # Orange
            'arista': '#2196F3',    # Blue
            'unknown': '#9E9E9E'    # Gray
        }

    def load_topology(self):
        """Load topology from JSON file"""
        try:
            with open(self.topology_file, 'r') as f:
                data = json.load(f)
                self.devices = data.get('devices', {})
                self.connections = data.get('connections', {})
            logger.info(f"Loaded topology from {self.topology_file}")
        except Exception as e:
            logger.error(f"Failed to load topology: {str(e)}")
            raise

    def build_graph(self):
        """Build NetworkX graph from topology data"""
        # Add all devices as nodes
        for device_name, device_info in self.devices.items():
            vendor = device_info.get('vendor', 'unknown')
            self.graph.add_node(
                device_name,
                vendor=vendor,
                hostname=device_info.get('hostname', ''),
                ip=device_info.get('ip', '')
            )

        # Add connections as edges
        added_edges = set()
        for local_device, connections in self.connections.items():
            for conn in connections:
                remote_device = conn['remote_device']
                local_port = conn['local_port']
                remote_port = conn['remote_port']

                # Avoid duplicate edges
                edge_key = tuple(sorted([local_device, remote_device]))
                if edge_key not in added_edges:
                    self.graph.add_edge(
                        local_device,
                        remote_device,
                        local_port=local_port,
                        remote_port=remote_port
                    )
                    added_edges.add(edge_key)

        logger.info(f"Graph built: {self.graph.number_of_nodes()} nodes, "
                   f"{self.graph.number_of_edges()} edges")

    def visualize_network(self, output_file: str = 'network_topology.png',
                         layout: str = 'spring', show_labels: bool = True,
                         show_ports: bool = True):
        """Create and save network visualization"""

        if self.graph.number_of_nodes() == 0:
            logger.warning("No nodes to visualize")
            return

        # Set up the plot
        fig, ax = plt.subplots(figsize=(20, 14))
        fig.patch.set_facecolor('white')
        ax.set_facecolor('#f5f5f5')

        # Choose layout algorithm
        if layout == 'spring':
            pos = nx.spring_layout(self.graph, k=2, iterations=50, seed=42)
        elif layout == 'circular':
            pos = nx.circular_layout(self.graph)
        elif layout == 'kamada_kawai':
            pos = nx.kamada_kawai_layout(self.graph)
        elif layout == 'shell':
            pos = nx.shell_layout(self.graph)
        else:
            pos = nx.spring_layout(self.graph)

        # Draw edges with port labels
        edge_colors = ['#666666' for _ in self.graph.edges()]
        nx.draw_networkx_edges(
            self.graph, pos,
            edge_color=edge_colors,
            width=2,
            alpha=0.6,
            ax=ax
        )

        # Draw edge labels (port information)
        if show_ports:
            edge_labels = {}
            for u, v, data in self.graph.edges(data=True):
                local_port = data.get('local_port', '')
                remote_port = data.get('remote_port', '')

                # Determine which device is which
                if u in self.connections:
                    for conn in self.connections[u]:
                        if conn['remote_device'] == v:
                            edge_labels[(u, v)] = f"{local_port}\n↕\n{remote_port}"
                            break
                elif v in self.connections:
                    for conn in self.connections[v]:
                        if conn['remote_device'] == u:
                            edge_labels[(u, v)] = f"{remote_port}\n↕\n{local_port}"
                            break

            nx.draw_networkx_edge_labels(
                self.graph, pos,
                edge_labels=edge_labels,
                font_size=7,
                font_color='#333333',
                bbox=dict(boxstyle='round,pad=0.3', facecolor='white', edgecolor='none', alpha=0.7),
                ax=ax
            )

        # Draw nodes with vendor-specific colors
        for vendor_type in set(nx.get_node_attributes(self.graph, 'vendor').values()):
            nodes_of_type = [n for n, d in self.graph.nodes(data=True)
                           if d.get('vendor') == vendor_type]
            color = self.vendor_colors.get(vendor_type, self.vendor_colors['unknown'])

            nx.draw_networkx_nodes(
                self.graph, pos,
                nodelist=nodes_of_type,
                node_color=color,
                node_size=3000,
                node_shape='s',
                alpha=0.9,
                linewidths=2,
                edgecolors='#333333',
                ax=ax
            )

        # Draw node labels
        if show_labels:
            labels = {}
            for node, data in self.graph.nodes(data=True):
                vendor = data.get('vendor', 'unknown').upper()
                ip = data.get('ip', '')
                labels[node] = f"{node}\n({vendor})\n{ip}"

            nx.draw_networkx_labels(
                self.graph, pos,
                labels=labels,
                font_size=9,
                font_weight='bold',
                font_color='white',
                ax=ax
            )

        # Create legend
        legend_elements = []
        for vendor, color in self.vendor_colors.items():
            if vendor != 'unknown':
                legend_elements.append(
                    mpatches.Patch(color=color, label=vendor.upper())
                )

        ax.legend(handles=legend_elements, loc='upper left',
                 fontsize=12, framealpha=0.9)

        # Add title with statistics
        title = (f"Network Topology Map\n"
                f"{self.graph.number_of_nodes()} Devices | "
                f"{self.graph.number_of_edges()} Connections")
        plt.title(title, fontsize=16, fontweight='bold', pad=20)

        ax.axis('off')
        plt.tight_layout()

        # Save figure
        plt.savefig(output_file, dpi=300, bbox_inches='tight',
                   facecolor='white', edgecolor='none')
        logger.info(f"Visualization saved to {output_file}")

        return fig

    def generate_text_report(self, output_file: str = 'network_topology.txt'):
        """Generate a text-based topology report"""
        with open(output_file, 'w') as f:
            f.write("=" * 80 + "\n")
            f.write("NETWORK TOPOLOGY REPORT\n")
            f.write("=" * 80 + "\n\n")

            f.write(f"Total Devices: {len(self.devices)}\n")
            f.write(f"Total Connections: {sum(len(c) for c in self.connections.values())}\n\n")

            f.write("DEVICES\n")
            f.write("-" * 80 + "\n")
            for device_name, device_info in sorted(self.devices.items()):
                f.write(f"\nDevice: {device_name}\n")
                f.write(f"  Vendor: {device_info.get('vendor', 'N/A').upper()}\n")
                f.write(f"  IP/Hostname: {device_info.get('hostname', 'N/A')}\n")

                if device_name in self.connections:
                    f.write(f"  Connections: {len(self.connections[device_name])}\n")

            f.write("\n\nCONNECTIONS\n")
            f.write("-" * 80 + "\n")
            for local_device, connections in sorted(self.connections.items()):
                f.write(f"\n{local_device}:\n")
                for conn in sorted(connections, key=lambda x: x['local_port']):
                    f.write(f"  {conn['local_port']:15} <--> "
                           f"{conn['remote_device']:20} ({conn['remote_port']})\n")

            f.write("\n" + "=" * 80 + "\n")

        logger.info(f"Text report saved to {output_file}")

    def generate_graphviz_dot(self, output_file: str = 'network_topology.dot'):
        """Generate GraphViz DOT file for advanced visualization"""
        with open(output_file, 'w') as f:
            f.write("graph NetworkTopology {\n")
            f.write("    layout=neato;\n")
            f.write("    overlap=false;\n")
            f.write("    splines=true;\n")
            f.write("    node [shape=box, style=filled, fontname=Arial];\n\n")

            # Write nodes
            for device_name, device_info in self.devices.items():
                vendor = device_info.get('vendor', 'unknown')
                color = self.vendor_colors.get(vendor, self.vendor_colors['unknown'])
                label = f"{device_name}\\n{vendor.upper()}\\n{device_info.get('ip', '')}"
                f.write(f'    "{device_name}" [label="{label}", fillcolor="{color}"];\n')

            f.write("\n")

            # Write edges
            added_edges = set()
            for local_device, connections in self.connections.items():
                for conn in connections:
                    remote_device = conn['remote_device']
                    edge_key = tuple(sorted([local_device, remote_device]))

                    if edge_key not in added_edges:
                        label = f"{conn['local_port']} - {conn['remote_port']}"
                        f.write(f'    "{local_device}" -- "{remote_device}" '
                               f'[label="{label}", fontsize=8];\n')
                        added_edges.add(edge_key)

            f.write("}\n")

        logger.info(f"GraphViz DOT file saved to {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Visualize LLDP Network Topology'
    )
    parser.add_argument('-i', '--input', required=True,
                       help='Input topology JSON file')
    parser.add_argument('-o', '--output', default='network_topology.png',
                       help='Output image file')
    parser.add_argument('-l', '--layout', default='spring',
                       choices=['spring', 'circular', 'kamada_kawai', 'shell'],
                       help='Graph layout algorithm')
    parser.add_argument('--no-ports', action='store_true',
                       help='Hide port labels')
    parser.add_argument('--text-report', action='store_true',
                       help='Generate text report')
    parser.add_argument('--dot-file', action='store_true',
                       help='Generate GraphViz DOT file')

    args = parser.parse_args()

    visualizer = NetworkVisualizer(args.input)
    visualizer.load_topology()
    visualizer.build_graph()

    # Generate visualization
    visualizer.visualize_network(
        output_file=args.output,
        layout=args.layout,
        show_ports=not args.no_ports
    )

    # Generate optional reports
    if args.text_report:
        base_name = args.output.rsplit('.', 1)[0]
        visualizer.generate_text_report(f"{base_name}.txt")

    if args.dot_file:
        base_name = args.output.rsplit('.', 1)[0]
        visualizer.generate_graphviz_dot(f"{base_name}.dot")

    logger.info("Visualization complete!")


if __name__ == '__main__':
    main()
