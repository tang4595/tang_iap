import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'iap_model.dart';

extension PurchaseUtil on PurchaseDetails {

  Map<String, dynamic> necessaryJsonInfo() {
    Map<String, dynamic> verificationDataJson = {
      'localVerificationData': verificationData.localVerificationData,
      'serverVerificationData': verificationData.serverVerificationData,
      'source': verificationData.source,
    };
    return {
      'productID': productID,
      'purchaseID': purchaseID,
      'transactionDate': transactionDate,
      'status': status.index,
      'pendingCompletePurchase': pendingCompletePurchase,
      'verificationData': verificationDataJson,
    };
  }
}

extension PurchaseNecessaryInfoUtil on IAPPurchaseNecessaryInfoModel {

  PurchaseDetails get toPurchaseDetails {
    final vd = PurchaseVerificationData(
      localVerificationData: verificationData?.localVerificationData ?? '',
      serverVerificationData: verificationData?.serverVerificationData ?? '',
      source: verificationData?.source ?? '',
    );
    final details = PurchaseDetails(
      productID: productID ?? '',
      verificationData: vd,
      purchaseID: purchaseID,
      transactionDate: transactionDate,
      status: PurchaseStatus.values[int.tryParse(status ?? '0') ?? 0],
    );
    details.pendingCompletePurchase = pendingCompletePurchase ?? false;
    return details;
  }
}

extension IapUtilStringExt on String {

  dynamic toJson() => jsonDecode(this);
  Map<String, dynamic>? toJsonMap() => jsonDecode(this) as Map<String, dynamic>;
}