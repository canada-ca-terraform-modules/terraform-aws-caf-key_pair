key_pairs = {
  admin = {} # Key defines the userDefinedString; {} makes the key pair "<env>-admin-key" at the apply and deletes it at the destroy,
  #            with the secret "keypair/<env>-admin-key" that holds its private key (the machine that applies needs bash and the AWS CLI)

  # --- A key pair that exists, or a public key of your own ---
  # existing = {
  #   key_name = "G3Cg-ops-admin" # A key pair that exists: looked up, the plan fails when it is missing; nothing is made
  # }
  # imported = {
  #   public_key = "ssh-ed25519 AAAAC3Nza... owner@host" # Imported as "<env>-imported-key"; you keep the private key
  # }

  # --- Naming ---
  # named = {
  #   name = "G3Cg-app-key" # Optional: the whole name instead of "<env>-<key>-key"; letters, digits, . _ -, at most 200
  # }

  # --- Where and with what the scripts run ---
  # via-role = {
  #   role_arn = "arn:aws:iam::123456789012:role/deploy" # Optional: the role the scripts assume (the stack's provider role); default the ambient credentials
  #   tags     = { owner = "team-x" }                    # Optional: merged with ESLZ-level tags, the module tag and the Name
  # }
}
