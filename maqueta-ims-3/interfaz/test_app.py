import unittest
from unittest.mock import Mock, patch

import app


UE_CONFIG = {
    "1": {
        "imsi": "001011234567890",
        "msisdn": "0010100001",
        "ki": "test-key",
        "port": "5061",
        "log": "pj1.log",
    },
    "2": {
        "imsi": "001011234567891",
        "msisdn": "0010100002",
        "ki": "test-key-2",
        "port": "5062",
        "log": "pj2.log",
    },
}


class ListenerTests(unittest.TestCase):
    @patch("app.sh", return_value=(0, "UNCONN 0 0 172.18.0.4:5060 0.0.0.0:*"))
    def test_listener_uses_netstat_when_ss_is_unavailable(self, run_command):
        self.assertTrue(app.listener_up("mims3_freeswitch", "5060"))
        run_command.assert_called_once_with(
            "mims3_freeswitch", "ss -lun 2>/dev/null || netstat -lun 2>/dev/null"
        )

    @patch("app.sh", return_value=(0, "UNCONN 0 0 172.18.0.4:8021 0.0.0.0:*"))
    def test_listener_rejects_a_different_open_port(self, _run_command):
        self.assertFalse(app.listener_up("mims3_freeswitch", "5060"))


class DnsTests(unittest.TestCase):
    @patch("app.sh", return_value=(0, "172.32.0.3 STREAM mims3_pcscf"))
    def test_resolve_ipv4_returns_service_vip(self, run_command):
        self.assertEqual(app.resolve_ipv4("mims3_softphone", "mims3_pcscf"), "172.32.0.3")
        run_command.assert_called_once_with(
            "mims3_softphone", "getent ahostsv4 mims3_pcscf"
        )

    @patch("app.sh", return_value=(2, ""))
    def test_resolve_ipv4_reports_unresolved_host(self, _run_command):
        self.assertIsNone(app.resolve_ipv4("mims3_softphone", "mims3_pcscf"))


class DockerRoutingTests(unittest.TestCase):
    def test_swarm_container_lookup_uses_service_group_proxy(self):
        container = Mock()
        client = Mock()
        client.containers.list.return_value = [container]
        clients = {"core": client, "database": Mock(), "ivr": Mock()}
        with patch("app.SWARM_MODE", True), patch("app.clients", clients):
            self.assertIs(app.get_container("mims3_pcscf"), container)

        client.containers.list.assert_called_once_with(
            filters={"label": "com.docker.swarm.service.name=mims3_pcscf"}
        )
        container.reload.assert_called_once_with()

    def test_swarm_container_lookup_rejects_unknown_service(self):
        with patch("app.SWARM_MODE", True):
            with self.assertRaisesRegex(ValueError, "Contenedor desconocido"):
                app.get_container("not-a-service")


class ImsClientTests(unittest.TestCase):
    @patch("app.container_ipv4", return_value="172.32.0.8")
    @patch("app.load_config", return_value=UE_CONFIG)
    def test_ue_command_uses_ims_aka_script_and_current_credentials(
        self, _load_config, _container_ip
    ):
        command = app.ue_command("1", "--play-file", "/tmp/voice message.wav")
        self.assertIn("UE1_IMSI=001011234567890", command)
        self.assertIn("UE1_MSISDN=0010100001", command)
        self.assertIn("UE1_KI=test-key", command)
        self.assertIn("IMS_PCSCF_IP=172.32.0.8", command)
        self.assertIn("/mnt/softphone/scripts/ue.sh 1", command)
        self.assertIn("--play-file '/tmp/voice message.wav'", command)
        self.assertNotIn("pjsua --id", command)

    @patch("app.container_ipv4", return_value="172.32.0.133")
    @patch("app.load_config", return_value=UE_CONFIG)
    def test_ue_command_uses_live_pcscf_task_ip_for_ipsec(
        self, _load_config, _container_ip
    ):
        command = app.ue_command("1")
        self.assertIn("IMS_PCSCF_IP=172.32.0.133", command)

    @patch(
        "app.sh",
        return_value=(
            0,
            'Response msg 401/REGISTER: user=001011234567890 '
            'WWW-Authenticate: Digest nonce="sensitive-nonce"',
        ),
    )
    def test_pjsua_diagnostics_redacts_authentication_and_subscriber_data(self, _sh):
        diagnostics = " ".join(app.pjsua_diagnostics("pj1.log"))
        self.assertIn("401/REGISTER", diagnostics)
        self.assertIn("[IMSI]", diagnostics)
        self.assertIn("[auth header redacted]", diagnostics)
        self.assertNotIn("sensitive-nonce", diagnostics)
        self.assertNotIn("001011234567890", diagnostics)

    @patch("app.sh", return_value=(0, ""))
    def test_pjsua_diagnostics_reports_empty_log(self, _sh):
        self.assertEqual(
            app.pjsua_diagnostics("pj1.log"),
            ["El log está vacío o no contiene errores SIP"],
        )

    @patch("app.sh", return_value=(0, ""))
    @patch("app.container_ipv4", return_value="172.32.0.8")
    @patch("app.load_config", return_value=UE_CONFIG)
    def test_registration_launcher_uses_ims_aka_script(
        self, _load_config, _container_ip, run_command
    ):
        app.launch_pjsua("1")
        self.assertEqual(run_command.call_count, 2)
        launch = run_command.call_args_list[1]
        self.assertIn("tail -f /dev/null |", launch.args[1])
        self.assertIn("/mnt/softphone/scripts/ue.sh 1", launch.args[1])
        self.assertIn("rm -f /tmp/pj1.log", launch.args[1])

    @patch("app.sh", return_value=(0, ""))
    @patch("app.wait_for", return_value=(True, "200 OK"))
    @patch("app.kill_sip")
    @patch("app.container_ipv4", return_value="172.32.0.8")
    @patch("app.load_config", return_value=UE_CONFIG)
    def test_call_launcher_uses_ims_aka_script(
        self, _load_config, _container_ip, _kill_sip, _wait_for, run_command
    ):
        app.ue_call("1", "0100002")
        launch = run_command.call_args_list[0]
        self.assertIn("/mnt/softphone/scripts/ue.sh 1", launch.args[1])
        self.assertIn("sip:0100002@", launch.args[1])
        self.assertIn("rm -f /tmp/pjC.log", launch.args[1])
        self.assertNotIn("pjsua --id", launch.args[1])


if __name__ == "__main__":
    unittest.main()
