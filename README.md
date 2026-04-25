# GATED

Garage Access Technology for Entry Detection

## Backend access

The backend reads allowed users from a text file and derives the single admin
account from `PRIMARY_ADMIN_EMAIL`:

- `gated/backend/allowed_emails.example.txt`

Local development can either create the real ignored files
`allowed_emails.txt` next to the backend `.env`, or rely on the example file as
a fallback.

## Admin area

The Admin tab manages allowed user emails and registered accounts. The primary
admin is visible in the table but cannot be edited or deleted. Resetting a user
password creates a temporary password and opens a prepared email draft for the
affected user.

Deployment docs for Raspberry Pi are available in `deploy/README.md`.
