from django.http import JsonResponse
from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView, TokenBlacklistView
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from apps.accounts.views import RegisterView, ProfileView, AccountView, ExportView, PasswordResetView, PasswordResetConfirmView
from apps.receipts.views import UploadView, ReceiptView, ReceiptListView
from apps.orders.views import OrderListView, OrderDetailView, RefundView, PaymentListView, PaymentImportView, PaymentLinkView
from apps.analytics.views import AnalyticsView


def health(_request):
    return JsonResponse({'status': 'ok'})


urlpatterns = [
    path('api/health/', health),
    path('api/v1/auth/register/', RegisterView.as_view()),
    path('api/v1/auth/login/', TokenObtainPairView.as_view()),
    path('api/v1/auth/refresh/', TokenRefreshView.as_view()),
    path('api/v1/auth/logout/', TokenBlacklistView.as_view()),
    path('api/v1/auth/password-reset/', PasswordResetView.as_view()),
    path('api/v1/auth/password-reset/confirm/', PasswordResetConfirmView.as_view()),
    path('api/v1/profile/', ProfileView.as_view()),
    path('api/v1/account/', AccountView.as_view()),
    path('api/v1/export/', ExportView.as_view()),
    path('api/v1/receipts/upload/', UploadView.as_view()),
    path('api/v1/receipts/', ReceiptListView.as_view()),
    path('api/v1/receipts/<int:pk>/<str:action>/', ReceiptView.as_view()),
    path('api/v1/orders/', OrderListView.as_view()),
    path('api/v1/orders/<int:pk>/', OrderDetailView.as_view()),
    path('api/v1/orders/<int:pk>/refunds/', RefundView.as_view()),
    path('api/v1/payments/', PaymentListView.as_view()),
    path('api/v1/payments/import/', PaymentImportView.as_view()),
    path('api/v1/payments/<int:pk>/link-order/', PaymentLinkView.as_view()),
    path('api/v1/analytics/<str:kind>/', AnalyticsView.as_view()),
    path('api/schema/', SpectacularAPIView.as_view()),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema')),
]
urlpatterns[-2].name = 'schema'
