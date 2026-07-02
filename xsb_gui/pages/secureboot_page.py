from xsb_gui.pages.migrate_page import _RunnerPage


class SecureBootPage(_RunnerPage):
    _subcommand = "enable-secureboot"
    _done_event = "secureboot_done"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setTitle("Enabling Secure Boot")
        self.setSubTitle("Creating and enrolling Secure Boot keys, then signing boot files.")
