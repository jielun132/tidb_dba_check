#!/usr/bin/env python3
"""Offline regression tests; no database, TiUP, or SSH connections."""
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1].joinpath('tidb_dba_check.sh').read_text()
parser = source[source.index('read_cluster_config() {'):source.index('# 提取指定集群的配置\nHOST_IPS=')]
cases = [
    ('[cluster:example]\nos_user=operator1\n[modules]\nos_user=wrong\n', 'os_user', 'operator1'),
    (' [cluster:example]  # comment\r\nosuser = operator1 # comment\r\n', 'os_user', 'operator1'),
    ('[cluster:example-other]\nos_user=wrong\n[cluster:example]\n# os_user=wrong\nos_user=operator1\n', 'os_user', 'operator1'),
    ('[cluster:other]\nos_user=wrong\n', 'os_user', ''),
    ('[cluster:example]\ndb_password = dummy#value=x\n', 'db_password', 'dummy#value=x'),
]
for config, key, expected in cases:
    with tempfile.NamedTemporaryFile(mode='w') as config_file:
        config_file.write(config)
        config_file.flush()
        result = subprocess.check_output(
            ['bash', '-c', parser + '\nCONFIG_FILE=$1; CLUSTER_NAME=example; read_cluster_config "$2"',
             'test', config_file.name, key], text=True)
        assert result.rstrip('\n') == expected, (key, result)

fetch = source[source.index('function fetch_config_value()'):source.index('declare -A GRPC_MAP')]
for mock, status, expected in [
    ('return 0', 0, ''),
    ('return 1', 1, ''),
    ("printf 'tikv\\t192.0.2.10:20160\\tserver.grpc-concurrency\\t5\\n'", 0, '192.0.2.10:20160 5\n'),
    ("printf 'invalid-row\\n'", 0, ''),
]:
    result = subprocess.run(['bash', '-c', 'run_sql() { ' + mock + '; };\n' + fetch +
                             '\nfetch_config_value server.grpc-concurrency'], capture_output=True, text=True)
    assert (result.returncode, result.stdout) == (status, expected), result

# Exercise the actual five loading loops with an empty producer.
loads = source[source.index('# grpc poll cpu ->'):source.index('function check_tikv_performance()')]
result = subprocess.run(['bash', '-c', 'fetch_config_value() { printf "\\n"; };\n' + loads],
                        capture_output=True, text=True)
assert result.returncode == 0 and not result.stderr, result
print('PASS: configuration isolation, aliases, CRLF, password preservation, SQL results, empty array keys')
