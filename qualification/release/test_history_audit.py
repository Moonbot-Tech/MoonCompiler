import contextlib
import io
import unittest
from unittest.mock import patch

import history_audit


class HistoryAuditTests(unittest.TestCase):
    def audit(self, author="Mike <mike@example.test>", message="Fix event waits"):
        def git(*args):
            if args[0] == "rev-parse":
                return "public"
            if args[0] == "ls-remote":
                return "public\trefs/heads/main"
            if args[0] == "log":
                return "Ivan <ivan@example.test>\nIvan <ivan@example.test>\nMike <mike@example.test>"
            if args[0] == "rev-list":
                return "candidate"
            if args[0] == "show":
                return f"{author}\n{author}\n{message}"
            self.fail(args)

        output = io.StringIO()
        with patch.object(history_audit, "git", side_effect=git), contextlib.redirect_stdout(output):
            status = history_audit.main()
        return status, output.getvalue()

    def test_published_author_after_another_contributor(self):
        self.assertEqual(self.audit()[0], 0)

    def test_unpublished_identity_rejected(self):
        status, output = self.audit(author="Unknown <unknown@example.test>")
        self.assertEqual(status, 1)
        self.assertIn("absent from published history", output)

    def test_metadata_rules_preserved(self):
        for message, reason in [("Исправление", "Cyrillic metadata"),
                                ("Fix\nGenerated-by: OpenAI", "AI attribution")]:
            with self.subTest(message=message):
                status, output = self.audit(message=message)
                self.assertEqual(status, 1)
                self.assertIn(reason, output)


if __name__ == "__main__":
    unittest.main()
