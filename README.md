# Beriwo

A Gemini-powered AI assistant that uses **Auth0 Token Vault** to securely access your Google services (Gmail, Calendar, Drive) through natural conversation.

Built for the [Authorized to Act Hackathon](https://authorizedtoact.devpost.com/).

## Architecture

```
Flutter App (Web + Android)
    → Auth0 Login (auth0_flutter)
    → Firebase Cloud Functions
        → Genkit Agent (Gemini)
        → Auth0 Token Vault (@auth0/ai-genkit)
            → Gmail API
            → Google Calendar API
            → Google Drive API
```

## Stack

- **Frontend:** Flutter (Web + Android)
- **Backend:** Firebase Cloud Functions (TypeScript)
- **AI:** Google Gemini via Firebase Genkit
- **Auth:** Auth0 + Token Vault (`@auth0/ai-genkit`)
- **Database:** Cloud Firestore

## Setup

### Prerequisites

- Node.js 20+
- Flutter 3.x
- Firebase CLI
- Auth0 account with Token Vault configured
- Google Cloud project with Gmail, Calendar, and Drive APIs enabled

### Backend

```bash
cd functions
cp .env.example .env   # Fill in your credentials
npm install
npm run build
```

### Flutter App

```bash
cd app
flutter pub get
flutter run -d chrome \
  --dart-define=AUTH0_DOMAIN=your-tenant.auth0.com \
  --dart-define=AUTH0_CLIENT_ID=your-client-id \
  --dart-define=API_BASE_URL=http://localhost:5001
```

### Auth0 Configuration

1. Create a Regular Web Application in Auth0
2. Configure Token Vault with Google social connection
3. Enable Gmail, Calendar, and Drive API scopes
4. Set up Connected Accounts for Token Vault

See [Auth0 Token Vault docs](https://auth0.com/ai/docs/intro/token-vault) for details.

## License

Apache-2.0
