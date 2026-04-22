class DB {
  static Future<void> saveCome(String login, String address) async {
    // тут сохранение time_in, address_in
  }

  static Future<void> saveLeave(String login, int rate, String address) async {
    // тут расчет и запись:
    // time_out, address_out, hours_worked, salary
  }
}
