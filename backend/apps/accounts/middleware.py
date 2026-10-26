from .models import AuditEvent


class AuditMiddleware:
    """Audit successful mutations without logging bodies, amounts or source text."""
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        user = getattr(request, 'user', None)
        if request.method in ['POST', 'PATCH', 'DELETE'] and response.status_code < 300 and user and user.is_authenticated and user.pk:
            view = getattr(getattr(request, 'resolver_match', None), 'func', None)
            resource = getattr(getattr(view, 'view_class', None), '__name__', 'api')
            AuditEvent.objects.create(user=user, action=request.method, resource=resource)
        return response
