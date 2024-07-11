class InAppPurchaseItem {
  final dynamic id;
  final String productId;
  String price;
  double priceValue;
  final String originalPrice;
  final double originalPriceValue;
  String currency;
  final String title;
  final String adTitle;

  InAppPurchaseItem({
    required this.id,
    required this.productId,
    required this.price,
    required this.priceValue,
    required this.originalPrice,
    required this.originalPriceValue,
    required this.currency,
    required this.title,
    required this.adTitle,
  });
}

class IAPPurchaseNecessaryInfoModel {
  String? productID;
  String? purchaseID;
  String? transactionDate;
  String? status;
  bool? pendingCompletePurchase;
  IAPPurchaseNecessaryInfoVerificationDataModel? verificationData;

  IAPPurchaseNecessaryInfoModel({
    this.productID,
    this.purchaseID,
    this.transactionDate,
    this.status,
    this.pendingCompletePurchase,
    this.verificationData,
  });

  IAPPurchaseNecessaryInfoModel.fromJson(dynamic json) {
    productID = json['productID'];
    purchaseID = json['purchaseID'];
    transactionDate = json['transactionDate'];
    status = '${json['status']}';
    pendingCompletePurchase = json['pendingCompletePurchase'];
    verificationData = IAPPurchaseNecessaryInfoVerificationDataModel
        .fromJson(json['verificationData'] ?? {});
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['productID'] = productID;
    map['purchaseID'] = purchaseID;
    map['transactionDate'] = transactionDate;
    map['status'] = status;
    map['pendingCompletePurchase'] = pendingCompletePurchase;
    map['verificationData'] = verificationData?.toJson() ?? {};
    return map;
  }
}

class IAPPurchaseNecessaryInfoVerificationDataModel {
  String? localVerificationData;
  String? serverVerificationData;
  String? source;

  IAPPurchaseNecessaryInfoVerificationDataModel({
    this.localVerificationData,
    this.serverVerificationData,
    this.source,
  });

  IAPPurchaseNecessaryInfoVerificationDataModel.fromJson(dynamic json) {
    localVerificationData = json['localVerificationData'];
    serverVerificationData = json['serverVerificationData'];
    source = json['source'];
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['localVerificationData'] = localVerificationData;
    map['serverVerificationData'] = serverVerificationData;
    map['source'] = source;
    return map;
  }
}