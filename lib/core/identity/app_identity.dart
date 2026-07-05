class AppIdentity {
  const AppIdentity({required this.displayName, required this.applicationId});

  static const defaultDisplayName = 'Calarm';
  static const defaultApplicationId = 'dev.xpa.calarm';
  static const current = AppIdentity(
    displayName: defaultDisplayName,
    applicationId: defaultApplicationId,
  );

  final String displayName;
  final String applicationId;
}
