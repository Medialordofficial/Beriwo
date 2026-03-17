const String auth0Domain = String.fromEnvironment(
  'AUTH0_DOMAIN',
  defaultValue: 'YOUR_TENANT.auth0.com',
);

const String auth0ClientId = String.fromEnvironment(
  'AUTH0_CLIENT_ID',
  defaultValue: 'YOUR_CLIENT_ID',
);

const String auth0Audience = String.fromEnvironment(
  'AUTH0_AUDIENCE',
  defaultValue: '',
);

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:5001',
);
