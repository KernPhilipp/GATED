# GATED

Garage Access Technology for Entry Detection

## Backend access files

The backend now reads allowed users and admins from text files instead of hard
coded addresses:

- `gated/backend/allowed_emails.example.txt`
- `gated/backend/admin_emails.example.txt`

Local development can either create the real ignored files
`allowed_emails.txt` / `admin_emails.txt` next to the backend `.env`, or rely
on the example files as a fallback.

## Admin area

Admins are managed through the backend role field (`User` / `Admin`) and the
new Admin tab in the Flutter app. Admin accounts are visible in the table but
cannot be edited or deleted. Resetting a user password creates a temporary
password and opens a prepared email draft for the affected user.

Deployment docs for Raspberry Pi are available in `deploy/README.md`.
