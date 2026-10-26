from .parsers import instamart, blinkit, zepto, bigbasket, generic

PARSERS = {'instamart': instamart.parse, 'blinkit': blinkit.parse, 'zepto': zepto.parse, 'bigbasket': bigbasket.parse, 'other': generic.parse}
