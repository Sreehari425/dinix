"""
Dinit-specific Machine class for the dinix test driver.

This extends the NixOS test driver's Machine class with dinit-specific
methods, replacing systemd-specific functionality.
"""

from test_driver.machine import QemuMachine


class DinitMachine(QemuMachine):
    """Machine with dinit-specific methods instead of systemd."""

    def wait_for_condition(self, condition: str, timeout: int = 900) -> None:
        """
        Wait for a Dinit service or task state.

        Args:
            condition: The dinit condition to wait for
            timeout: Maximum time to wait in seconds
        """
        parts = condition.split("/")
        if len(parts) < 2 or parts[0] not in ("service", "task"):
            raise ValueError(
                "Dinit conditions are not queryable through dinitctl; "
                "use a service/task condition or wait_until_succeeds()"
            )
        service = parts[1] if parts[0] == "service" else f"task-{parts[1]}"
        with self.nested(f"waiting for Dinit service '{service}'"):
            self.wait_until_succeeds(f"dinitctl status {service}", timeout=timeout)

    def wait_for_runlevel(self, level: int, timeout: int = 900) -> None:
        """
        Wait for dinit to reach a specific runlevel.

        Args:
            level: The runlevel number (0-9, S)
            timeout: Maximum time to wait in seconds
        """
        with self.nested(f"waiting for runlevel {level}"):
            self.wait_for_console_text(f"entering runlevel {level}", timeout=timeout)

    def dinitctl(self, cmd: str) -> tuple[int, str]:
        """
        Run an dinitctl command.

        Args:
            cmd: The dinitctl subcommand and arguments

        Returns:
            Tuple of (exit_code, output)
        """
        return self.execute(f"dinitctl {cmd}")

    def wait_for_service(self, service: str, timeout: int = 900) -> None:
        """
        Wait for a dinit service to be running.

        Args:
            service: The service name
            timeout: Maximum time to wait in seconds
        """
        self.wait_for_condition(f"service/{service}/running", timeout=timeout)

    def wait_for_task(self, task: str, timeout: int = 900) -> None:
        """
        Wait for a dinit task to complete successfully.

        Args:
            task: The task name
            timeout: Maximum time to wait in seconds
        """
        self.wait_for_condition(f"task/{task}/success", timeout=timeout)

    def start_service(self, service: str) -> tuple[int, str]:
        """
        Start a dinit service.

        Args:
            service: The service name

        Returns:
            Tuple of (exit_code, output)
        """
        return self.dinitctl(f"start {service}")

    def stop_service(self, service: str) -> tuple[int, str]:
        """
        Stop a dinit service.

        Args:
            service: The service name

        Returns:
            Tuple of (exit_code, output)
        """
        return self.dinitctl(f"stop {service}")

    def reload_service(self, service: str) -> tuple[int, str]:
        """
        Reload a dinit service configuration.

        Args:
            service: The service name

        Returns:
            Tuple of (exit_code, output)
        """
        return self.dinitctl(f"reload {service}")

    def get_service_status(self, service: str) -> tuple[int, str]:
        """
        Get the status of a dinit service.

        Args:
            service: The service name

        Returns:
            Tuple of (exit_code, output)
        """
        return self.dinitctl(f"status {service}")

    # override systemd-specific methods to prevent accidental use
    def wait_for_unit(
        self, unit: str, user: str | None = None, timeout: int = 900
    ) -> None:
        """Raises error - use wait_for_service() or wait_for_condition() instead."""
        raise NotImplementedError(
            f"wait_for_unit('{unit}') is systemd-specific. "
            f"Use wait_for_service('{unit}') or wait_for_condition() instead."
        )

    def systemctl(self, q: str, user: str | None = None) -> tuple[int, str]:
        """Raises error - use dinitctl() instead."""
        raise NotImplementedError(
            "systemctl() is systemd-specific. Use dinitctl() instead."
        )

    def get_unit_info(self, unit: str, user: str | None = None) -> dict[str, str]:
        """Raises error - use get_service_status() instead."""
        raise NotImplementedError(
            f"get_unit_info('{unit}') is systemd-specific. "
            f"Use get_service_status('{unit}') instead."
        )
