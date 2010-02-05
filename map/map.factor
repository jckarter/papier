! (c)2010 Joe Groff bsd license
USING: accessors alien assocs classes.struct combinators
combinators.short-circuit fry gpu.shaders images images.atlas
images.loader io.directories io.encodings.utf8 io.files
io.pathnames json.reader kernel locals math math.matrices.simd
math.vectors.simd sequences sets specialized-arrays
strings typed ;
FROM: alien.c-types => float ;
SPECIALIZED-ARRAY: float
IN: papier.map

ERROR: bad-papier-version version ;

CONSTANT: papier-map-version 3

: check-papier-version ( hash -- hash )
    "papier" over at dup papier-map-version = [ drop ] [ bad-papier-version ] if ;

TUPLE: slab
    { image string }
    { center float-4 }
    { size float-4 }
    { orient float-4 }
    { color float-4 }
    { matrix matrix4 }
    { texcoords float-4 } ;

VERTEX-FORMAT: papier-vertex
    { "vertex"   float-components 3 f }
    { f          float-components 1 f }
    { "texcoord" float-components 2 f }
    { f          float-components 2 f }
    { "color"    float-components 4 f } ;
STRUCT: papier-vertex-struct
    { vertex   float-4 }
    { texcoord float-4 }
    { color    float-4 } ;
SPECIALIZED-ARRAY: papier-vertex-struct

ERROR: bad-matrix-dim matrix ;

: parse-slab ( hash -- image center size orient color )
    {
        [ "image"  swap at ]
        [ "center" swap at 3 0.0 pad-tail 4 1.0 pad-tail >float-4 ]
        [ "size"   swap at                4 1.0 pad-tail >float-4 ]
        [ "orient" swap at                               >float-4 ]
        [ "color"  swap at                               >float-4 ]
    } cleave ;

TYPED: slab-matrix ( slab: slab -- matrix: matrix4 )
    [ center>> translation-matrix4 ]
    [ size>> scale-matrix4 m4. ]
    [ orient>> q>matrix4 m4. ] tri ;

TYPED: update-slab ( slab: slab -- )
    dup slab-matrix >>matrix drop ;

TYPED: <slab> ( image center size orient color -- slab: slab )
    slab new
        swap >>color
        swap >>orient
        swap >>size
        swap >>center
        swap >>image
    dup update-slab ;

TYPED: update-slab-for-atlas ( slab: slab images -- )
    [ dup image>> ] dip at >float-4 >>texcoords drop ;

: update-slabs-for-atlas ( slabs images -- )
    '[ _ update-slab-for-atlas ] each ; inline

: parse-papier-map ( hash -- slabs )
    check-papier-version
    "slabs" swap at [ parse-slab <slab> ] map ;

: load-papier-map ( path name -- slabs )
    append-path utf8 file-contents json> parse-papier-map ;

: load-papier-images ( path -- images atlas )
    [
        [ file-extension "tiff" = ] filter [ dup load-image ] H{ } map>assoc
    ] with-directory-files make-atlas-assoc ;
