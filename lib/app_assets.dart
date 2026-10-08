class AppAssets {
  static const _add = 'assets/Chicken_Rush_additional_assets';
  static const _game = 'assets/Chicken_Rush_gameplay_assets';

  static const icon = '$_add/Icon.webp';
  static const gameName = '$_add/Game_name.webp';
  static const loadingVertical = '$_add/Vertical_Loading_Screen.webp';
  static const loadingHorizontal = '$_add/Horizontal_Loading_Screen.webp';
  static const notificationsVertical = '$_add/Vertical_Notifications_Screen.webp';
  static const notificationsHorizontal =
      '$_add/Horizontal_Notifications_Screen.webp';

  static const logo = '$_game/Game_Name_2_asset.webp';
  static const sign = '$_game/red_carpet_asset.webp';
  static const bgStart = '$_game/bg_start_asset.webp';
  static const bgStart2 = '$_game/bg_start_2_asset.webp';
  static const bgLines = '$_game/bg_lines_asset.webp';
  static const bgEnd = '$_game/bg_end_asset.webp';
  static const barrier = '$_game/Barrier_asset.webp';
  static const chicken = '$_game/chicken_asset.webp';
  static const chickenDead = '$_game/chicken_dead_asset.webp';
  static const feathers = '$_game/Feathers_asset.webp';
  static const hatchGold = '$_game/hatch_gold_asset.webp';
  static const hatchGray = '$_game/hatch_gray_asset.webp';
  static const bush1 = '$_game/bush1_asset.webp';
  static const bush2 = '$_game/bush2_asset.webp';

  static const cars = [
    '$_game/Car_Taxi_asset.webp',
    '$_game/Car_Police_asset.webp',
    '$_game/Car_FireFighter_asset.webp',
    '$_game/Car_Van_asset.webp',
  ];

  static const gameplay = [
    logo,
    bgStart,
    bgStart2,
    bgLines,
    bgEnd,
    barrier,
    chicken,
    chickenDead,
    feathers,
    hatchGold,
    hatchGray,
    sign,
    gameName,
    ...cars,
  ];
}
