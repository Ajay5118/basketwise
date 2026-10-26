from rest_framework import serializers


class DetailSerializer(serializers.Serializer):
    detail = serializers.CharField()


class PasswordSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True)


class ResetSerializer(serializers.Serializer):
    email = serializers.EmailField()


class ResetConfirmSerializer(PasswordSerializer):
    uid = serializers.CharField()
    token = serializers.CharField()


class AlertSerializer(serializers.Serializer):
    text = serializers.CharField(max_length=4000)
    source_identifier = serializers.CharField(max_length=128, required=False)


class LinkSerializer(serializers.Serializer):
    order = serializers.IntegerField()


class ReceiptStatusSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    status = serializers.CharField()
    error = serializers.CharField()
    order_id = serializers.IntegerField(allow_null=True)
    data = serializers.JSONField(required=False)


class UploadSerializer(serializers.Serializer):
    file = serializers.FileField()


class OverviewSerializer(serializers.Serializer):
    gross_spending = serializers.DecimalField(max_digits=14, decimal_places=2)
    net_spending = serializers.DecimalField(max_digits=14, decimal_places=2)
    confirmed_refunds = serializers.DecimalField(max_digits=14, decimal_places=2)
    order_count = serializers.IntegerField()
    average_order_value = serializers.DecimalField(max_digits=14, decimal_places=2)
    this_month = serializers.JSONField()
    last_month = serializers.JSONField()
    change_percent = serializers.CharField(allow_null=True)
    platforms = serializers.ListField(child=serializers.JSONField())
