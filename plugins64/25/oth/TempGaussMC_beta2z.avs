#            ===============
#              TempGaussMC
#            ===============
#  (version: something point something, beta-2)
#
#   A motion-compensated bob deinterlacer, based on temporal gaussian blurring
#
#   
#   Responsible for the impossible: Did�e
#  
#   
#   DISCLAIMER:
#   - This bobber does NOT leave the original fields unchanged!
#   - Moreover, it reduces noise/grain of the source!
#  (**Not true anymore** as of beta-2, which can use the "lossless" option: original fields are kept, noise reduction is less.)
#
#   Overall, the output is rich of detail, and probably the most calm/stable you've ever got from a bob deinterlacer. ;-)
#
#   REQUIRED PLUGINS: 
#   - MVTools2
#   - RemoveGrain + Repair
#   - VerticalCleaner
#   - MaskTools v2
#   - nnedi3 / nnedi2 / nnedi / EEDI2 / Yadif , depending on which EdiMode you want to use
#
#     VariableBlur: Not used anymore, because of a serious memory leak in BinomialBlur(). (Replaced with other filters giving the same result.)
#    ( v1u (unofficial, by Terranigma): Modded to use MVTools2 and added "nnedi2" as an interpolater option. Kudos to Did�e for an amazing script. ;-)
#    ( v1u2 (unofficial, by Terranigma) : fixed chroma shifting thanks to "thewebchat", and added a parameter to change rfilter method's. Previously & permanently set to mvtools2's default [2]
#    ( v2u (unofficial, by Terranigma): included "nnedi3" as an Interpolator option, added nnedi3's "nns" parameter, and replaced "NNEDI" with "nnedi" as henryho_hk felt that the naming scheme was suboptimal. =P
#    ( beta-3 (unofficial, by Leinad4Mind): mix beta2mod version (mod for MVTools 1.9.7.7 & 2.x by thetoof; stage2 Chroma shift correction has been disabled with MVTools2 since it has been corrected in MVTools 1.10.2.1.) with v1u2 and v2u, 

function TempGaussMC_beta2z(clip clp, int "tr0", int "tr1", int "tr2", int "rep0", int "rep1", int "rep2", string "EdiMode", int "nsize", int "nns", int "qual", int "EEDI2maxd",
 \                          int "lossless", float "sharpness", int "Smode", int "SLmode", int "SLrad", float "Sbb", float "SVthin", int "Sovs", 
 \                          int "blocksize", int "overlap", bool "truemotion", bool "globalmtn",
 \                          int "rfilter", int "search", int "searchparam", int "pelsearch", int "sharp", int "lambda", int "DCT", int "pnew", int "plevel", int "lsad",
 \                          int "SCth1", int "SCth2", int "thSAD1", int "thSAD2",
 \                          float "pel2hr", bool "border", int "draft", clip "edeint",
 \	    		             bool "MT")
{
clp

# Defaults for temporal gauss filtering
tr0       = default( tr0,       2 )    #  temporal radius for temporal Gauss before motion compensation (1 or 2)
tr1       = default( tr1,       2 )    #  temporal radius for temporal Gauss with motion compensation (1 or 2)
tr2       = default( tr2,       1 )    #  temporal radius for final MVDegrain (1, 2 or 3)

# Defaults for EDI interpolation
EdiMode   = default( EdiMode,"EEDI2")  #  interpolator to use: "nnedi3", "nnedi2", "nnedi", "EEDI2" "Yadif". Any other string: use plain bicubic bob (fast!)
nsize     = default( nsize, 2 )        #  nnedi2/nnedi3 only: Sets the size of the local neighborhood around each pixel that is used by the predictor neural network. For deinterlacing, larger x_diameter settings will allow connecting lines of smaller slope. 0-2 for nnedi2; 0-4 for nnedi3. Possible settings (x_diameter x y_diameter): 0 (8x6), 1 (16x6), 2 (32x6), 3 (48x6), 4 (8x4)
nns       = default( nns,   1 )        #  nnedi3 only: "Speed" vs. "Quality" option. Sets the number of neurons in the predictor neural network. Settings ranges from 0 to 3 (3 being the best/slowest). 0 (32), 1 (64), 2 (128), or 3 (256)
qual      = default( qual, 1 )         #  nnedi2/nnedi3 only: Controls the number of different neural network predictions that are blended together to compute the final output value. Each neural network was trained on a different set of training data. Blending the results of these different networks improves generalization to unseen data. Possible values are 1-3 for nnedi2, and 1 or 2 for nnedi3. Essentially this is a quality vs speed option. Larger values will result in more processing time, but should give better results
EEDI2maxd = default( EEDI2maxd, 8 )    #  EEDI2 interpolation only: spatial search distance value  

# Defaults for temp-gauss reparation
rep0      = default( rep0,      4 )    #  repair temporalsoften-defects for searchclip
rep1      = default( rep1,      0 )    #  repair MVDegrain-defects for output (stage1)
rep2      = default( rep2,      4 )    #  repair MVDegrain-defects for output (stage2)

lossless  = default( lossless, -1 )    #  "Lossless" mode will leave the original fields unchanged, i.e. the original input can be extracted from the result again
                                       #  -1: deactivated (the old lossy mode)
                                       #   0: dumb-weave of orig-fields and TGMC-interpolated fields. Not good! It's only available as to try and see WHY it's not good. ;-)
                                       #   1: dumb-weave with weak spatial anticomb. Not really recommended. May suffice for sources with sufficiently strong lowpass.
                                       #   2: MC'ed temporal compensation (normal) followed by spatial anticomb. Better for sharp sources. Little less stable than "3".
                                       #   3: MC'ed temporal compensation (stronger) followed by spatial anticomb. More stable than "2".


# Defaults for contra-sharpening of the temp-gauss'ed clip
sharp0    = default( sharpness, 0.25+(tr1+tr2)/6.) # strength of sharpening, 0.0 to 1.0, or more if you like
Smode     = default( Smode,     2 )    #  Which method to use for re-sharpening the MC'ed temporal gauss:
                                       #    0 = not at all
                                       #    1 = 3x3 kernel
                                       #    2 = vertical min/max  plus  3x3 kernel
SLmode    = default( SLmode,    2 )    #  How to limit the sharpening: 
                                       #    0 = not at all
                                       #    1 = spatial, before 2nd MV stage      (fast)
                                       #    2 = MC-temporal, before 2nd MV stage  (slow)
                                       #    3 = spatial, after 2nd MV stage       (fast)
                                       #    4 = MC-temporal, after 2nd MV stage   (slow)
SLrad     = default( SLrad,     1 )    #  How much prev+next temporal neighbors to consider for sharpness limiting (SLmode = 2|4),
                                       #  resp. spatial radius for spatial sharpness limiting mode (SLmode = 1|3)
Sbb       = default( Sbb,       1 )    #  Back-blending of gauss-blurred sharpen's difference (slightly increases visual fidelity)
                                       #    0 = no back-blending
                                       #    1 = before sharp-limiting
                                       #    2 = after sharp-limiting
                                       #    3 = before AND after sharp-limiting
SVthin    = default( SVthin,  1.0 )    #  Vertical thinning of broadened horizontal edges. 0.0=OFF  0.5=weak  3.0=strrrong
Sovs      = default( Sovs,      0 )    #  Allowed "overshoot" for sharpness limiting (a little cheating, that is)

# Defaults for important MV-parameters
_bs       = default( blocksize,16 )    #  Blocksize for motion search
_ovlp     = default( overlap,_bs/2)    #  Overlap size for ME blocks
_tm       = default( truemotion,false) #  Whether to use MVAnalyse's "truemotion" defaults
_global   = default( globalmtn, true)  #  "global" parameter of MVAnalyse

# Defaults for "less important" MV-parameters
_rfilter  = default( rfilter,   0 )    #  smoothing method: refer to the mvtools2 doc for more detail.
_search   = default( search,    2 )    #  search method
_ME       = default( searchparam,2)    #  search depth
_pelsrch  = default( pelsearch, 2 )    #  accuracy of pel level search: 1 = fast, 2 = accurate
_shrp     = default( sharp,     2 )    #  sharpness of subpel interpolation
_DCT      = default( DCT,       0 )    #  DCT mode. Various modes may help or may harm ... default is 0 = OFF
_lambda   = default( lambda, _tm ? 1000* _bs*_bs /64 : 0 )   # vector coherence
_pnew     = default( pnew,   _tm ? 50 : 0 )                  # penalty for new vectors over predicted vectors
_plevel   = default( plevel, _tm ?  1 : 0 )                  # lamda level scaling mode
_lsad     = default( lsad,   _tm ? 1200*_bs*_bs/64 : 400*_bs*_bs/64 ) # local lambda resetting threshold

# Scenechange thresholds and MVDegrain thSAD value. 
# ***** DO NOT TOUCH WITHOUT SPECIFIC REASON *****
_SCth1    = default( SCth1,     180 )  #  SAD threshold for "bad blocks" 
_SCth2    = default( SCth2,      98 )  #  percentage of bad blocks to trigger a scenechange
_thSAD1   = default( thSAD1, 5* 128 )  #  SAD threshold for 1st MVDegrain (gaussian stage)  
_thSAD2   = default( thSAD2, 2* 128 )  #  SAD threshold for 2nd MVDegrain (linear stage)

# other stuff
border    = default( border,   true )  #  true = padd borders internally to catch "half scanlines" at top + bottom (broadcast material)
draft     = default( draft,       0 )  #  '1' outputs a quick draft, and '2' is even more draft'ier  :p
pel2hr    = default( pel2hr,    0.0 )  #  0.0 is OFF.  0.1 ~ 0.3 can be useful to reduce halo-amplifying of pel=2 subsampling 
MT	  = default( MT,      false )  #  true = use the multithreaded branch of MVtools
ST	  = mt ? false : true 		# Single-thread


# parameter adjustments for internal usage
sharpness = default(sharpness, (SLmode==1||SLmode==3) ? sharp0 : 2*sharp0 ) # temporal limiting can afford more than spatial limiting
ed0       = rep0<10 ? rep0 : rep0/10
od0       = rep0<10 ?    0 : rep0-ed0*10
ed1       = rep1<10 ? rep1 : rep1/10
od1       = rep1<10 ?    0 : rep1-ed1*10
ed2       = rep2<10 ? rep2 : rep2/10
od2       = rep2<10 ?    0 : rep2-ed2*10
trmax     = (tr1 > tr2) ? tr1 : tr2
use1      = (trmax > 0) ? true : false
use2      = (trmax > 1) ? true : false
use3      = (trmax > 2 || SLrad>1) ? true : false
thinn     = SVthin * 6.0


#---------------------------------------------------------------------------------------------------
# Let's start doing something.

nullclip  = blankclip(clp,width=16,height=16) 

# if "border" is requested, apply padding by 4 pixels at top & bottom
clp = (border) ? clp.pointresize(clp.width(),clp.height()+8, 0,-4,-0,clp.height()+8.001 )
 \             : clp
ox = clp.width()
oy = clp.height()

# Create spatially interpolated bob-clips
dbob = clp.bob(0,0.5)
edi  = (EdiMode=="nnedi3") ? clp.nnedi3(field=-2,nsize=nsize,nns=nns,qual=qual)
 \   : (EdiMode=="nnedi2") ? clp.nnedi2(field=-2,nsize=nsize,qual=qual)
 \   : (EdiMode=="nnedi")  ? clp.nnedi(field=-2)
 \   : (EdiMode=="EEDI2") ? clp.SeparateFields().EEDI2(field=-2, maxd=EEDI2maxd) 
 \   : (EdiMode=="Yadif") ? clp.Yadif(mode=1)
 \                         : dbob

edi = defined(edeint) ? edeint.pointresize(ox,oy, 0,(edeint.height()-oy)/2,-0,oy+.001 ) : edi

# create linearily weighted temporal averaging
t1 = dbob.temporalsoften(1,255,255,28,2)
t2 = dbob.temporalsoften(2,255,255,28,2)

# construct temporal gaussian average from linear averages
t  = (tr0==0) ? dbob
 \ : (tr0==1) ? t1.merge(dbob,0.25)
 \            : t1.merge(t2,0.357).merge(dbob,0.125)

# IF rep0=true: Allow only bob-typical vertical differences
t1 = t.VCRep(dbob,ed=ed0,od=od0)
t2 = (rep0!=0) ? t1 : t

# Create clip for motion search.
# Trick: weight-in a gaussian blur, to reduce local contrast of searchclip. (Needed to later make MVDegrain work as expected ...the "SAD concept" doesn't fit
#                                                                            to the realities -- so, let's tailor the realities to fit the darn concept ...)
t3=mt_lutxy(t2,dbob,"x 3 + y < x 3 + x 3 - y > x 3 - y ? ?",U=3,V=3) # small cheat for better motion search
searchclip = t2.removegrain(11).gaussresize(ox,oy,0,0,ox+.0001,oy+.0001,p=2)
 \             .merge(t2,0.1).mt_lutxy(t3,"x 7 + y < x 2 + x 7 - y > x 2 - x 51 * y 49 * + 100 / ? ?",U=3,V=3)


# Get motion vectors
_pel  = 2

searchclipsuper = st ? searchclip.MSuper(pel=_pel,sharp=_shrp, levels=0, rfilter=_rfilter) : nullclip

allv = 						      MT ?	searchclip.MVAnalyseMulti(refframes=3, truemotion=_tm,pel=_pel,sharp=_shrp,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                               				global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad,idx=6) : nullclip

bvec3   = (use3 && MT) ? allv.MVMultiExtract(0) : (use3) ? 	searchclipsuper.MAnalyse(isb=true, delta=3,truemotion=_tm,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                                                     global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad) : nullclip  # ,sadx264=3
 
bvec2   = (use2 && MT) ? allv.MVMultiExtract(1) : (use2) ? 	searchclipsuper.MAnalyse(isb=true, delta=2,truemotion=_tm,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                                                     global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad) : nullclip  # ,sadx264=3
 
bvec1   = (use1 && MT) ? allv.MVMultiExtract(2) : (use1) ?	searchclipsuper.MAnalyse(isb=true, delta=1,truemotion=_tm,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                                                 global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad) : nullclip  # ,sadx264=3
 
fvec1   = (use1 && MT) ? allv.MVMultiExtract(3) : (use1) ? 	searchclipsuper.MAnalyse(isb=false,delta=1,truemotion=_tm,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                                                 global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad) : nullclip  # ,sadx264=3
 
fvec2   = (use2 && MT) ? allv.MVMultiExtract(4) : (use2) ? 	searchclipsuper.MAnalyse(isb=false,delta=2,truemotion=_tm,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                                                 global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad) : nullclip  # ,sadx264=3
 
fvec3   = (use3 && MT) ? allv.MVMultiExtract(5) : (use3) ? 	searchclipsuper.MAnalyse(isb=false,delta=3,truemotion=_tm,blksize=_bs,overlap=_ovlp,lambda=_lambda,pnew=_pnew,
 \                                                 global=_global,search=_search,searchparam=_ME,pelsearch=_pelsrch,DCT=_DCT,plevel=_plevel,lsad=_lsad) : nullclip  # ,sadx264=3

vec1	= MT ? allv.MVMultiExtract(2,3) : nullclip
vec2	= MT ? allv.MVMultiExtract(1,4) : nullclip
deg2	= MT ? allv.MVMultiExtract(1,2,3,4) : nullclip


# create motion compensated temporal averaging with linear weighting
edisuper= st ? edi.MSuper(pel=_pel,sharp=_shrp, levels=1, rfilter=_rfilter) : nullclip
mvdg1   =            MT ? edi.MVDegrainMulti(vec1,     thSAD=_thSAD1,thSCD1=_SCth1,thSCD2=_SCth2,idx=7) : 	    edi.MDegrain1(edisuper,bvec1,fvec1,            thSAD=_thSAD1,thSCD1=_SCth1,thSCD2=_SCth2)
mvdg2   = (tr1>1 && MT) ? edi.MVDegrainMulti(vec2,      thSAD=_thSAD1,thSCD1=_SCth1,thSCD2=_SCth2,idx=7) : (tr1>1) ? edi.MDegrain1(edisuper,            bvec2,fvec2,thSAD=_thSAD1,thSCD1=_SCth1,thSCD2=_SCth2) : nullclip

# create explicit motion compensations (needed for SLmode = 2|4)
comp_fw1 = (SLmode==2 || SLmode==4)         ?  st ? edi.MCompensate(edisuper,fvec1,thSCD1=_SCth1,thSCD2=_SCth2) : edi.MVCompensate(fvec1,thSCD1=_SCth1,thSCD2=_SCth2,idx=7) : nullclip
comp_bw1 = (SLmode==2 || SLmode==4)         ?  st ? edi.MCompensate(edisuper,bvec1,thSCD1=_SCth1,thSCD2=_SCth2) : edi.MVCompensate(bvec1,thSCD1=_SCth1,thSCD2=_SCth2,idx=7) : nullclip
comp_fw3 = (SLmode==2 || SLmode==4)&& use3  ?  st ? edi.MCompensate(edisuper,fvec3,thSCD1=_SCth1,thSCD2=_SCth2) : edi.MVCompensate(fvec3,thSCD1=_SCth1,thSCD2=_SCth2,idx=7) : nullclip
comp_bw3 = (SLmode==2 || SLmode==4)&& use3  ?  st ? edi.MCompensate(edisuper,bvec3,thSCD1=_SCth1,thSCD2=_SCth2) : edi.MVCompensate(bvec3,thSCD1=_SCth1,thSCD2=_SCth2,idx=7) : nullclip

# cheap halo-reduction for sharp pel modes (for Lmode=2|4)
cx1=comp_fw1.width()
cx3=comp_fw3.width()
cy1=comp_fw1.height()
cy3=comp_fw3.width()
comp_fw1 = (pel2hr==0.0) ?  comp_fw1 :  comp_fw1.mergeluma(comp_fw1.removegrain(11,-1).gaussresize(cx1,cy1,0,0,cx1+.0001,cy1+.0001,p=5),pel2hr)
comp_fw3 = (pel2hr==0.0) ?  comp_fw3 :  comp_fw3.mergeluma(comp_fw3.removegrain(11,-1).gaussresize(cx3,cy3,0,0,cx3+.0001,cy3+.0001,p=5),pel2hr)
comp_bw1 = (pel2hr==0.0) ?  comp_bw1 :  comp_bw1.mergeluma(comp_bw1.removegrain(11,-1).gaussresize(cx1,cy1,0,0,cx1+.0001,cy1+.0001,p=5),pel2hr)
comp_bw3 = (pel2hr==0.0) ?  comp_bw3 :  comp_bw3.mergeluma(comp_bw3.removegrain(11,-1).gaussresize(cx3,cy3,0,0,cx3+.0001,cy3+.0001,p=5),pel2hr)
     
# figure local min & max over given temporal window (for Lmode=2|4)
pmax = (SLrad>0) ? edi .mt_logic(comp_fw1,"max",U=3,V=3).mt_logic(comp_bw1,"max",U=3,V=3) : edi
pmax = (SLrad>1) ? pmax.mt_logic(comp_fw3,"max",U=3,V=3).mt_logic(comp_bw3,"max",U=3,V=3) : pmax
pmin = (SLrad>0) ? edi .mt_logic(comp_fw1,"min",U=3,V=3).mt_logic(comp_bw1,"min",U=3,V=3) : edi
pmin = (SLrad>1) ? pmin.mt_logic(comp_fw3,"min",U=3,V=3).mt_logic(comp_bw3,"min",U=3,V=3) : pmin

# create motion-compensated temporal gaussian blur
stage1  = (tr1==0) ? edi
 \      : (tr1==1) ? mvdg1.merge(edi,0.25)
 \                 : mvdg1.merge(mvdg2,0.2).merge(edi,0.0625)

# IF rep1=true: Allow only bob-typical vertical differences
stage1 = (rep1!=0) ? stage1.VCRep(edi,ed=ed1,od=od1) : stage1


# calculate vertical median (for thinning), and vertical min-max-average (for sharpening)
#vmedD   = mt_luts(stage1,stage1,mode="median",pixels="0 -1 0 0 0 1",yexpr="128 x y - "+string(thinn)+" * -",U=1,V=1).blur(1,0) # too slow!
vmedD   = mt_lutxy(stage1,stage1.VerticalCleaner(mode=1),yexpr="128 x y - "+string(thinn)+" * -",U=1,V=1).blur(1,0) # much faster!
vmedDD  = mt_lutxy(vmedD,vmedD.removegrain(11,-1),"y 128 - abs x 128 - abs > y 128 ?")
st1mmavg =  mt_average( stage1.mt_expand(mode="vertical",U=3,V=3),stage1.mt_inpand(mode="vertical",U=3,V=3),U=3,V=3 )
 \         .mt_lutxy(stage1,"x y < x 1 + x y > x 1 - x ? ?",U=3,V=3)

# re-sharpen the temporal gaussian blur 
stage1a = (Smode==0) ? stage1
 \      : (Smode==1) ? stage1.mt_lutxy(stage1.removegrain(11),"x x y - "+string(sharpness)+" * +",U=3,V=3)
 \                   : stage1.mt_lutxy(st1mmavg.removegrain(11),"x x y - "+string(sharpness)+" * +",U=3,V=3)

# apply vertical thinning?
stage1a = (SVthin==0.0) ? stage1a : stage1a.mt_adddiff(vmedDD,U=2,V=2)

# apply 1st sharpening back-blending?
stage1a = ((Sbb==1 || Sbb==3) && Smode!=0 && sharpness!=0.0) 
 \       ? stage1a.mt_makediff(mt_makediff(stage1a,stage1,U=1,V=1).removegrain(11,-1).gaussresize(ox,oy,0,0,ox+.0001,oy+.0001,p=5),U=2,V=2) 
 \       : stage1a

# apply sharpening limiting? (SLmode 1|2)
stage1b = (sharpness==0.0) ? stage1 
 \                         : (SLmode==1) ? ( (SLrad<2) ? stage1a.repair(edi,1) : stage1a.repair(stage1a.repair(edi,12),1) )
 \                         : (SLmode==2) ? stage1a.mt_clamp(pmax,pmin,Sovs,Sovs,U=3,V=3)
 \                                       : stage1a

# apply 2nd sharpening back-blending?
stage1b = ((Sbb==2 || Sbb==3) && Smode!=0 && sharpness!=0.0) 
 \       ? stage1b.mt_makediff(mt_makediff(stage1b,stage1,U=1,V=1).gaussresize(ox,oy,0,0,ox+.0001,oy+.0001,p=5),U=2,V=2) 
 \       : stage1b
    
# final temporal filter for stabilisation, motion-compensated
stage1bsuper= st ? stage1b.MSuper(pel=_pel, sharp=_shrp, levels=1, rfilter=_rfilter) : nullclip
stage2  = (tr2==0) ? stage1b
 \      : (tr2==1 && MT) ? stage1b.MVDegrainMulti(vec1,thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2,idx=8) : (tr2==1) ? stage1b.MDegrain1(stage1bsuper,bvec1,fvec1,                        thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2)
 \      : (tr2==2 && MT) ? stage1b.MVDegrainMulti(deg2,thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2,idx=8) : (tr2==2) ? stage1b.MDegrain2(stage1bsuper,bvec1,fvec1,bvec2,fvec2,            thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2)
 \                 : MT  ? stage1b.MVDegrainMulti(allv,thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2,idx=8) : 	     stage1b.MDegrain3(stage1bsuper,bvec1,fvec1,bvec2,fvec2,bvec3,fvec3,thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2)

# IF rep2=true: Allow only bob-typical vertical differences
stage2  = (rep2!=0) ? stage2.VCRep(edi,ed=ed2,od=od2) : stage2

## (The below has been fixed in MVTools v2 branch. But what about josey well's MT-branch (based on v1.9) ?? )
## MVDegrain causes a chroma shift (yes it does, with pel>1 !)  We compensate by shifting chroma towards plain EDI by a small notch 
## [ 1+(x-1)/(1+(x/5)^4) ] on 128-centered diff-clip (x-y) ==>  [ x y - abs 2 < y x x y - abs 1 - 1 x y - abs 5 / 4 ^ + / 1 + x y - x y - abs 0.0001 + / * + ? ]
## mod : disabled with MVTools2 since it has been corrected in MVTools 1.10.2.1
stage2 = mt ? stage2.mt_lutxy(edi,"x y - abs 2 < y x x y - abs 1 - 1 x y - abs 5 / 4 ^ + / 1 + x y - x y - abs 0.0001 + / * - ?",Y=2,U=3,V=3) : stage2
 
 
# apply sharpness limiting (SLmode 3|4), or has "draft" been requested?
stage3  = (draft==2)   ?  t  .subtitle("Draft 2")
 \      : (draft==1)   ?  t1 .subtitle("Draft 1")
 \      : (SLmode==3)  ?  ( (SLrad<2) ? stage2.repair(edi,1) : stage2.repair(stage2.repair(edi,12),1) )
 \      : (SLmode==4)  ?  stage2.mt_clamp(pmax,pmin,Sovs,Sovs,U=3,V=3)
 \                     :  stage2


# "Lossless" stage
#==================
# Get difference orig.fields - TGMC'ed orig-fields, then motion-compensate that diff, apply result to the interpolated fields.
    stage4   = getparity(clp) ? stage3.assumetff() : stage3.assumebff()
                     stage4.separatefields()
    ofields_tgmc   = selectevery(4,0,3)
    newfields_tgmc = selectevery(4,1,2)
    ofields  = clp.separatefields()
    dumb     = interleave(ofields,newfields_tgmc).selectevery(4,0,1,3,2).weave()
    diff     = mt_makediff(ofields_tgmc,ofields,U=3,V=3)
    diff2    = interleave(diff,diff.mt_lut("x",Y=-128,U=-128,V=-128)).selectevery(4,0,1,3,2).weave()
    diff2sup = diff2.MSuper(pel=_pel,sharp=_shrp,levels=1)
    diff3    = (lossless==3) ? diff2.MDegrain3(diff2sup,bvec1,fvec1,bvec1,fvec1,bvec1,fvec1,thSAD=_thSAD2,thSCD1=_SCth1,thSCD2=_SCth2)
     \                       : diff2.MDegrain2(diff2sup,bvec1,fvec1,bvec1,fvec1)
    diff3_newfields = diff3.separatefields().selectevery(4,1,2)
    newfields_corr  = newfields_tgmc.mt_makediff(diff3_newfields,U=3,V=3)
    corr1    = (lossless>1) ? interleave(ofields,newfields_corr).selectevery(4,0,1,3,2).weave()
     \                      : dumb

# some combing still may be there. Cleanup based on a simple vertical-median. No magic, it catches some, but not all combing.
# (Any way of reliably eliminating ALL signs of combing will also destroy lots of good signal, resulting in bob shimmer again.)
# This is a rather conservative compromise.

    med1     = corr1.verticalcleaner(mode=1)
    med1D    = mt_makediff(corr1,med1,U=3,V=3)
    q2       = med1D.separatefields().selectevery(4,1,2)
    q22      = q2.verticalcleaner(mode=1).mt_lutxy(q2,"x 128 - y 128 - * 0 < 128 x 128 - abs y 128 - abs < x y ? ?",U=3,V=3)
    q222     = q22.repair(q22.removegrain(2),1)
    corr2    = interleave(ofields,newfields_corr.mt_makediff(q222,U=3,V=3)).selectevery(4,0,1,3,2).weave()

    stage99 = (lossless==-1) ? stage4
     \      : (lossless== 0) ? dumb
     \                       : corr2

    
## brute-force calming when the motion tool finds too much motion. Better don't use.
# stage99 = stage99.ttempsmooth(2,6,6,2,2,strength=5,pfclip=searchclip)

# A simple doodad: MFlowFPS-SlowMotion, using the already calculated vectors 
# factor = 4   #  =>  1/4 speed
##---------------------------------
# sup99=stage99.MSuper(pel=_pel,sharp=_shrp,levels=1)
# stage99 = stage99.MFlowFPS(sup99,bvec1,fvec1,num=factor*FramerateNumerator(edi),den=FramerateDenominator(edi)).assumefps(Framerate(edi))


# if "border" was active, crop it back again
(border) ? stage99.crop(0,4,-0,-4)
 \       : stage99

return( last )
}

#===================================================================================================

# Re-builds of mt_inflate & mt_deflate. These rebuilds are faster than the originals.

function TGMC_inflate(clip c,int"Y",int "U",int "V") {
mtY=default(Y, 3) mtU=default(U, 1) mtV=default(V, 1)
rgY=(mtY==3)?20:-1 rgU=(mtU==3)?20:-1 rgV=(mtV==3)?20:-1 
mt_logic(c,c.removegrain(rgY,rgU,rgV),"max",Y=mtY,U=mtU,V=mtV) }

function TGMC_deflate(clip c,int"Y",int "U",int "V") {
mtY=default(Y, 3) mtU=default(U, 1) mtV=default(V, 1)
rgY=(mtY==3)?20:-1 rgU=(mtU==3)?20:-1 rgV=(mtV==3)?20:-1 
mt_logic(c,c.removegrain(rgY,rgU,rgV),"min",Y=mtY,U=mtU,V=mtV) }


# helper function: compare two clips, and allow only differences that are bob-typical
function VCRep(clip clp, clip ref, int "ed", int "od")
{
ed = default(ed,1)  #  e'rosion d'istance: 1 = minimum, 5 = maximum
od = default(od,0)  #  o'ver-d'ilation of the eroded difference: 0=no, 1=somewhat, 2=somewhat more, 3=one full pixel

tD_2   = mt_makediff(ref,clp,U=3,V=3) 

tD1_2  = (ed>=3)        ? tD_2 .mt_inpand(mode="vertical",U=3,V=3) :   tD_2
tD1_2  =                  tD1_2.mt_inpand(mode="vertical",U=3,V=3) 
tD1_2  = (ed!=0&&ed!=3) ? tD1_2.TGMC_deflate(U=3,V=3)                :   tD1_2
tD1_2  = (ed==2||ed==5) ? tD1_2.removegrain(4)                     :   tD1_2
tD1_2  =                  tD1_2.mt_expand(mode="vertical",U=3,V=3)
tD1_2  = (ed>=2) ?        tD1_2.mt_expand(mode="vertical",U=3,V=3) :   tD1_2
tD1_2  = (ed>=5) ?        tD1_2.mt_expand(mode="vertical",U=3,V=3) :   tD1_2
tD1_2  = (od==0) ?        tD1_2 
 \     : (od==1) ?        tD1_2.TGMC_deflate(U=3,V=3) 
 \     : (od==2) ?        tD1_2.TGMC_deflate(U=3,V=3).TGMC_deflate(U=3,V=3)
 \               :        tD1_2.mt_expand(U=3,V=3)

tD2_2  = (ed>=3)        ? tD_2 .mt_expand(mode="vertical",U=3,V=3) :   tD_2
tD2_2  =                  tD2_2.mt_expand(mode="vertical",U=3,V=3) 

tD2_2  = (ed!=0&&ed!=3) ? tD2_2.TGMC_inflate(U=3,V=3)                :   tD2_2
tD2_2  = (ed==2||ed==5) ? tD2_2.removegrain(4)                     :   tD2_2
tD2_2  =                  tD2_2.mt_inpand(mode="vertical",U=3,V=3)
tD2_2  = (ed>=2) ?        tD2_2.mt_inpand(mode="vertical",U=3,V=3) :   tD2_2
tD2_2  = (ed>=5) ?        tD2_2.mt_inpand(mode="vertical",U=3,V=3) :   tD2_2
tD2_2  = (od==0) ?        tD2_2 
 \     : (od==1) ?        tD2_2.TGMC_deflate(U=3,V=3) 
 \     : (od==2) ?        tD2_2.TGMC_deflate(U=3,V=3).TGMC_deflate(U=3,V=3)
 \               :        tD2_2.mt_inpand(U=3,V=3)

tDD_2  = tD_2.mt_lutxy(tD1_2,"x 129 < x y 128 < 128 y ? ?",U=3,V=3).mt_lutxy(tD2_2,"x 127 > x y 128 > 128 y ? ?",U=3,V=3)
clp.mt_adddiff(tDD_2,U=3,V=3)
}