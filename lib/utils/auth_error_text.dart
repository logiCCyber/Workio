String friendlyResetPasswordError(Object error) {
  final raw = error.toString();

  // Самое частое: 429 лимит
  if (raw.contains('statusCode: 429') ||
      raw.contains('rate limit') ||
      raw.contains('over_email_send_rate_limit')) {
    return 'Too many reset requests.\nTry again in a few minutes.';
  }

  // Если email не найден / неверный
  if (raw.toLowerCase().contains('email') && raw.toLowerCase().contains('not found')) {
    return 'Email not found.\nCheck the address and try again.';
  }

  // Общий случай
  return 'Something went wrong.\nPlease try again.';
}
