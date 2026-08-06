#!/bin/bash
# Simple Zimbra password reset tool

# Generate random 12-character password (letters and numbers only)
generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12
}

echo "========================================"
echo "     Zimbra's Password Reset Tool"
echo "========================================"
read -p "Enter user email: " USER_EMAIL

# Check if user exists
if ! zmprov -l ga "$USER_EMAIL" &>/dev/null; then
    echo "ERROR: User '$USER_EMAIL' does not exist"
    echo ""
    echo "Tip: Use 'zmprov -l gaa' to list all users"
    exit 1
fi

# Generate random password
NEW_PASSWORD=$(generate_password)

# Reset password and force change
if zmprov -l sp "$USER_EMAIL" "$NEW_PASSWORD" && \
   zmprov -l ma "$USER_EMAIL" zimbraPasswordMustChange TRUE; then
    echo ""
    echo "========================================"
    echo "              ✅ SUCCESS"
    echo "========================================"
    echo "📧 Email:    $USER_EMAIL"
    echo "🔑 Password: $NEW_PASSWORD"
    echo "📌 Status:   Must change on next login"
    echo "========================================"
    echo ""
    echo "User will be prompted to change password on first login"
else
    echo "❌ ERROR: Failed to reset password for $USER_EMAIL"
    exit 1
fi