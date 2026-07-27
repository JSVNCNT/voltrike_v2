import '../../../data/models/app_user.dart';
import '../../../data/models/driver.dart';

enum AccountAccessStatus { active, suspended, underReview }

class AccountAccessPolicy {
  const AccountAccessPolicy._();

  static AccountAccessStatus evaluate({required AppUser user, Driver? driver}) {
    if (!user.isActive) return AccountAccessStatus.suspended;
    if (!user.isDriver) return AccountAccessStatus.active;
    if (driver?.isSuspended == true) return AccountAccessStatus.suspended;
    if (driver?.isApproved != true) return AccountAccessStatus.underReview;
    return AccountAccessStatus.active;
  }
}
