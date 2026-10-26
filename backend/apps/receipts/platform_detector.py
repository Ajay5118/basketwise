def detect(text):
    lower = text.lower()
    for slug, words in {'instamart': ['instamart'], 'blinkit': ['blinkit'], 'zepto': ['zepto'], 'bigbasket': ['bigbasket', 'big basket']}.items():
        if any(word in lower for word in words):
            return slug
    return 'other'
