function EEDI2(clip clip, int "mthresh", int "lthresh", int "vthresh", int "estr", int "dstr", int "maxd", int "field", int "map", int "nt", int "pp")
{
VersionNumber() < 2.60 ? LoadPlugin(AviSynthPlugins64Dir + "25/EEDI2.dll") : LoadPlugin(AviSynthPlugins64Dir + "26/EEDI2.dll")
        EEDI2(clip, mthresh, lthresh, vthresh, estr, dstr, maxd, field, map, nt, pp)
}