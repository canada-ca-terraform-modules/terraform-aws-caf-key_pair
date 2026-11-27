"""Tests for the key pair scripts of the module (bin/create_key_pair.sh and bin/delete_key_pair.sh) with a stub aws: the private key goes from the key pair call to the secret call's stdin and
nowhere else (no argument, no output), an existing key pair or secret stops it before anything is made, and a failed secret deletes
the new key pair. A stub cannot prove the key never touches a disk: the pipe is the design."""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "bin" / "create_key_pair.sh"
DELETE_SCRIPT = Path(__file__).resolve().parent.parent / "bin" / "delete_key_pair.sh"
MATERIAL = "-----BEGIN RSA PRIVATE KEY-----\nSECRETMATERIAL\n-----END RSA PRIVATE KEY-----"
NAME = "G3Pg-firewall-admin"

STUB = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
echo "$1 $2 key=${AWS_ACCESS_KEY_ID-}" >> "$STUB_LOG.env"
case "$1 $2" in
  "sts get-caller-identity") echo 294135371530 ;;
  "sts assume-role") printf 'ASSUMEDKEY\tASSUMEDSECRET\tASSUMEDTOKEN\n' ;;
  "configure get") echo ca-central-1 ;;
  "ec2 describe-key-pairs") echo "${STUB_KEY_EXISTS-None}" ;;
  "secretsmanager list-secrets")
    [ -z "$STUB_LIST_FAIL" ] || exit 1
    # After a delete the secret is still listed for STUB_LAG more calls: Secrets Manager is eventually consistent.
    if [ -f "$STUB_LOG.deleted" ]; then
      left=$(cat "$STUB_LOG.deleted")
      if [ "$left" -gt 0 ]; then echo "${STUB_SECRET_EXISTS-}"; echo $((left - 1)) > "$STUB_LOG.deleted"; fi
    else
      echo "${STUB_SECRET_EXISTS-}"
    fi ;;
  "ec2 create-key-pair")
    [ -z "$STUB_CREATE_FAIL" ] || exit 1
    printf '%s\\n' "$STUB_MATERIAL" ;;
  "secretsmanager create-secret")
    cat > "$STUB_LOG.secret"
    exit "${STUB_SECRET_FAIL-0}" ;;
  "ec2 delete-key-pair") exit "${STUB_DELETE_FAIL-0}" ;;
  "secretsmanager delete-secret")
    echo "${STUB_LAG-0}" > "$STUB_LOG.deleted"
    exit "${STUB_SECRET_DELETE_FAIL-0}" ;;
esac
"""


class CreateKeyPair(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "aws"
        stub.write_text(STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        self.log = self.tmp / "calls"
        env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "STUB_LOG": str(self.log), "STUB_MATERIAL": MATERIAL}
        env.pop("AWS_REGION", None)
        env.pop("AWS_DEFAULT_REGION", None)
        self.env = env

    script = SCRIPT

    def run_script(self, *args, **env):
        return subprocess.run([str(self.script), *args], env={**self.env, **env}, capture_output=True, text=True)

    def keys_seen_after_the_first_call(self):
        return {line.split("key=")[1] for line in Path(f"{self.log}.env").read_text().splitlines()[1:]}

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def commands(self):
        return [" ".join(call.split()[:2]) for call in self.calls()]

    def test_makes_the_key_pair_and_pipes_its_private_key_into_the_secret_only(self):
        result = self.run_script(NAME)
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertEqual(commands[:4], ["sts get-caller-identity", "configure get", "ec2 describe-key-pairs", "secretsmanager list-secrets"])
        # The two ends of the pipe run at once, so the order of their log lines is not defined.
        self.assertEqual(sorted(commands[4:]), ["ec2 create-key-pair", "secretsmanager create-secret"])
        calls = {call.split()[0] + " " + call.split()[1]: call for call in self.calls()}
        self.assertIn("--key-type rsa --key-format pem --query KeyMaterial --output text", calls["ec2 create-key-pair"])
        self.assertIn(f"--name keypair/{NAME}", calls["secretsmanager create-secret"])
        self.assertIn("--secret-string file:///dev/stdin", calls["secretsmanager create-secret"])
        self.assertEqual(Path(f"{self.log}.secret").read_text().strip(), MATERIAL)
        self.assertNotIn("SECRETMATERIAL", "\n".join(self.calls()) + result.stdout + result.stderr)

    def test_prints_the_account_and_region_before_it_makes_anything(self):
        result = self.run_script(NAME)
        self.assertIn("Account 294135371530, Region ca-central-1", result.stdout)
        result = self.run_script(NAME, AWS_REGION="ca-west-1", STUB_KEY_EXISTS=NAME)
        self.assertIn("Region ca-west-1", result.stdout)

    def test_an_existing_key_pair_stops_before_anything_is_made(self):
        result = self.run_script(NAME, STUB_KEY_EXISTS=NAME)
        self.assertEqual(result.returncode, 1)
        self.assertIn("already exists", result.stderr)
        self.assertIn(f"aws ec2 delete-key-pair --key-name {NAME}", result.stderr)
        self.assertNotIn("ec2 create-key-pair", self.commands())

    def test_an_existing_or_deleting_secret_stops_before_the_key_pair_is_made(self):
        result = self.run_script(NAME, STUB_SECRET_EXISTS=f"keypair/{NAME}")
        self.assertEqual(result.returncode, 1)
        self.assertIn("scheduled for deletion", result.stderr)
        self.assertNotIn("ec2 create-key-pair", self.commands())
        list_call = [c for c in self.calls() if c.startswith("secretsmanager list-secrets")][0]
        self.assertIn("--include-planned-deletion", list_call)

    def test_a_secret_that_cannot_be_made_deletes_the_new_key_pair(self):
        result = self.run_script(NAME, STUB_SECRET_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls()[-1], f"ec2 delete-key-pair --key-name {NAME}")
        self.assertIn("was deleted", result.stderr)

    def test_a_delete_that_fails_says_to_delete_the_key_pair_by_hand(self):
        result = self.run_script(NAME, STUB_SECRET_FAIL="1", STUB_DELETE_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("delete it by hand", result.stderr)

    def test_a_key_pair_that_cannot_be_made_deletes_nothing_and_stores_nothing(self):
        result = self.run_script(NAME, STUB_CREATE_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("ec2 delete-key-pair", self.commands())
        self.assertFalse(Path(f"{self.log}.secret").read_text().strip())

    def test_a_name_that_is_not_a_key_name_is_a_usage_error(self):
        for args in ([], ["a", "b"], ["bad name"], ["a/b"], ["x" * 201]):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_a_role_arn_is_assumed_before_anything_is_made_and_its_credentials_are_used(self):
        role = "arn:aws:iam::294135371530:role/lz-poc-deploy"
        result = self.run_script(NAME, KEY_PAIR_ROLE_ARN=role)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands()[0], "sts assume-role")
        self.assertIn(f"--role-arn {role}", self.calls()[0])
        self.assertEqual(self.keys_seen_after_the_first_call(), {"ASSUMEDKEY"})
        self.assertNotIn("ASSUMEDSECRET", "\n".join(self.calls()) + result.stdout + result.stderr)

    def test_tags_go_on_the_key_pair_and_the_secret(self):
        tags = '[{"Key":"Name","Value":"G3Pg-firewall-key"},{"Key":"owner","Value":"team x"}]'
        result = self.run_script(NAME, KEY_PAIR_TAGS=tags)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = {call.split()[0] + " " + call.split()[1]: call for call in self.calls()}
        self.assertIn('--tag-specifications [{"ResourceType":"key-pair","Tags":' + tags + "}]", calls["ec2 create-key-pair"])
        self.assertIn(f"--tags {tags}", calls["secretsmanager create-secret"])

    def test_no_tags_adds_no_tag_argument(self):
        self.run_script(NAME)
        self.assertNotIn("--tag", "\n".join(self.calls()))


class DeleteKeyPair(CreateKeyPair):
    script = DELETE_SCRIPT

    def test_deletes_the_key_pair_and_the_secret_without_a_recovery_window(self):
        result = self.run_script(NAME, STUB_SECRET_EXISTS=f"keypair/{NAME}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.commands(),
            [
                "sts get-caller-identity",
                "configure get",
                "ec2 delete-key-pair",
                "secretsmanager list-secrets",
                "secretsmanager delete-secret",
                "secretsmanager list-secrets",
            ],
        )
        calls = {call.split()[0] + " " + call.split()[1]: call for call in self.calls()}
        self.assertIn(f"--key-name {NAME}", calls["ec2 delete-key-pair"])
        self.assertIn(f"--secret-id keypair/{NAME}", calls["secretsmanager delete-secret"])
        self.assertIn("--force-delete-without-recovery", calls["secretsmanager delete-secret"])
        self.assertIn("Account 294135371530, Region ca-central-1", result.stdout)

    def test_an_absent_secret_is_not_deleted_and_is_no_error(self):
        result = self.run_script(NAME)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("secretsmanager delete-secret", self.commands())

    def test_a_secret_scheduled_for_deletion_is_deleted_for_good(self):
        result = self.run_script(NAME, STUB_SECRET_EXISTS=f"keypair/{NAME}")
        self.assertIn("--include-planned-deletion", [c for c in self.calls() if c.startswith("secretsmanager list-secrets")][0])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_key_pair_that_cannot_be_deleted_fails_and_leaves_the_secret(self):
        result = self.run_script(NAME, STUB_DELETE_FAIL="1", STUB_SECRET_EXISTS=f"keypair/{NAME}")
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not be deleted", result.stderr)
        self.assertNotIn("secretsmanager delete-secret", self.commands())

    def test_a_secret_that_cannot_be_deleted_fails(self):
        result = self.run_script(NAME, STUB_SECRET_DELETE_FAIL="1", STUB_SECRET_EXISTS=f"keypair/{NAME}")
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not be deleted", result.stderr)

    def test_waits_until_the_secret_is_no_longer_listed_so_a_new_key_of_the_same_name_can_be_made_at_once(self):
        result = self.run_script(NAME, STUB_SECRET_EXISTS=f"keypair/{NAME}", STUB_LAG="2", KEY_PAIR_WAIT_SECONDS="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands().count("secretsmanager list-secrets"), 1 + 2 + 1)

    def test_a_secret_that_stays_listed_fails_after_the_tries(self):
        result = self.run_script(NAME, STUB_SECRET_EXISTS=f"keypair/{NAME}", STUB_LAG="100", KEY_PAIR_WAIT_SECONDS="0", KEY_PAIR_WAIT_TRIES="3")
        self.assertEqual(result.returncode, 1)
        self.assertIn("still listed", result.stderr)
        self.assertEqual(self.commands().count("secretsmanager list-secrets"), 1 + 3)

    def test_a_failing_list_is_an_error_and_not_an_absence(self):
        result = self.run_script(NAME, STUB_LIST_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("deleted", result.stdout.split("deleting", 1)[-1])
        self.assertNotIn("secretsmanager delete-secret", self.commands())

    def test_with_a_required_tag_only_what_carries_it_is_deleted(self):
        result = self.run_script(
            NAME,
            KEY_PAIR_REQUIRE_TAG="module=terraform-aws-caf-key_pair",
            STUB_KEY_EXISTS=NAME,
            STUB_SECRET_EXISTS=f"keypair/{NAME}",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        describe = [c for c in calls if c.startswith("ec2 describe-key-pairs")][0]
        self.assertIn(f"Name=key-name,Values={NAME}", describe)
        self.assertIn("Name=tag:module,Values=terraform-aws-caf-key_pair", describe)
        listing = [c for c in calls if c.startswith("secretsmanager list-secrets")][0]
        self.assertIn("Key=tag-key,Values=module", listing)
        self.assertIn("Key=tag-value,Values=terraform-aws-caf-key_pair", listing)
        self.assertIn("ec2 delete-key-pair", self.commands())
        self.assertIn("secretsmanager delete-secret", self.commands())

    def test_a_key_pair_and_a_secret_without_the_required_tag_are_left_alone(self):
        # A name collision makes the create fail and leaves it tainted; the destroy that follows must not delete a key it never made.
        result = self.run_script(NAME, KEY_PAIR_REQUIRE_TAG="module=terraform-aws-caf-key_pair")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("ec2 delete-key-pair", self.commands())
        self.assertNotIn("secretsmanager delete-secret", self.commands())
        self.assertIn("left alone", result.stdout)

    # What the create tests above check of the shared parts does not apply to the delete script.
    test_tags_go_on_the_key_pair_and_the_secret = None
    test_no_tags_adds_no_tag_argument = None
    test_makes_the_key_pair_and_pipes_its_private_key_into_the_secret_only = None
    test_prints_the_account_and_region_before_it_makes_anything = None
    test_an_existing_key_pair_stops_before_anything_is_made = None
    test_an_existing_or_deleting_secret_stops_before_the_key_pair_is_made = None
    test_a_secret_that_cannot_be_made_deletes_the_new_key_pair = None
    test_a_delete_that_fails_says_to_delete_the_key_pair_by_hand = None
    test_a_key_pair_that_cannot_be_made_deletes_nothing_and_stores_nothing = None


if __name__ == "__main__":
    unittest.main()
