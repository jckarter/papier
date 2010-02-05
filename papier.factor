! (c)2010 Joe Groff bsd license
USING: accessors alien.c-types alien.data.map arrays
combinators fry game.input game.input.scancodes game.loop
game.worlds gpu gpu.buffers gpu.framebuffers gpu.render
gpu.shaders gpu.state gpu.textures hashtables images kernel
literals math math.matrices.simd math.order math.vectors
math.vectors.simd papier.map sequences sorting ui ui.gadgets
ui.gadgets.worlds ui.gestures ui.pixel-formats ;
FROM: math.matrices => frustum-matrix4 translation-matrix4 ;
IN: papier

CONSTANT: eye-distance 5.0
CONSTANT: near-plane 0.25
CONSTANT: fov 0.7
CONSTANT: far-plane 1024.0
CONSTANT: move-rate 0.05
CONSTANT: eye-drag-factor 0.01
CONSTANT: slab-buffer-chunk-size 1024

GLSL-SHADER-FILE: papier-vertex-shader vertex-shader "papier.v.glsl"
GLSL-SHADER-FILE: papier-fragment-shader fragment-shader "papier.f.glsl"
GLSL-PROGRAM: papier-program
    papier-vertex-shader papier-fragment-shader ;

UNIFORM-TUPLE: papier-uniforms
    { "p_matrix" mat4-uniform    f }
    { "eye"      vec3-uniform    f }
    { "atlas"    texture-uniform f } ;

TUPLE: papier-world < game-world
    { slabs array }
    { slab-images hashtable }
    { vertex-buffer buffer }
    { index-buffer buffer }
    { vertex-array vertex-array }
    { uniforms papier-uniforms }

    { editing? boolean }

    drag-slab
    slab-drag-base ;

: <p-matrix> ( papier-world -- matrix )
    dim>> dup first2 min >float v/n fov v*n near-plane v*n
    near-plane far-plane frustum-matrix4 ; inline

: init-state ( -- )
        ! T{ triangle-cull-state { cull cull-back } }
    {
        T{ blend-state { rgb-mode T{ blend-mode } } { alpha-mode T{ blend-mode } } }
    } set-gpu-state ;

: load-into-world ( world path -- )
    [ "map" load-papier-map >>slabs ] [
        load-papier-images
        [ >>slab-images ] [ [ dup uniforms>> atlas>> 0 ] dip allocate-texture-image ] bi*
    ] bi
    [ slabs>> ] [ slab-images>> ] bi update-slabs-for-atlas ; 

: start-editing ( world -- )
    "start edit" P.
    t >>editing?
    game-loop>> stop-loop ;

: stop-editing ( world -- )
    "stop edit" P.
    f >>editing?
    game-loop>> start-loop ;

M: papier-world handle-gesture
    dup editing?>>
    [ call-next-method ]
    [ 2drop t ] if ;

M: papier-world begin-game-world
    init-gpu
    init-state
    
    stream-upload draw-usage index-buffer  slab-buffer-chunk-size f <buffer> >>index-buffer
    stream-upload draw-usage vertex-buffer slab-buffer-chunk-size f <buffer>
        [ >>vertex-buffer ]
        [ papier-program <program-instance> papier-vertex buffer>vertex-array >>vertex-array ] bi

    papier-uniforms new
        over <p-matrix> >>p_matrix
        float-4{ 0.0 0.0 $ eye-distance 0.0 } >>eye
        RGBA ubyte-components T{ texture-parameters
            { min-mipmap-filter f }
        } <texture-2d> >>atlas
    >>uniforms

    "vocab:papier/sample.papier" load-into-world ;

: ctrl-tab? ( keys -- ? )
    [ key-tab swap nth ]
    [ key-left-control swap nth ]
    [ key-right-control swap nth ] tri or and ; inline

: move-eye ( world amount -- )
    [ uniforms>> ] dip '[ _ v+ ] change-eye drop ; inline

: keyboard-input ( papier-world -- )
    [ read-keyboard keys>> ] dip 
    key-left-arrow  pick nth [ dup float-4{ $ move-rate 0.0 0.0 0.0 } vneg move-eye ] when
    key-right-arrow pick nth [ dup float-4{ $ move-rate 0.0 0.0 0.0 }      move-eye ] when
    key-down-arrow  pick nth [ dup float-4{ 0.0 $ move-rate 0.0 0.0 } vneg move-eye ] when
    key-up-arrow    pick nth [ dup float-4{ 0.0 $ move-rate 0.0 0.0 }      move-eye ] when
    key-escape      pick nth [ dup close-window ] when
    over ctrl-tab? [ dup start-editing ] when
    2drop ; inline

: start-drag-slab ( world -- )
    drop ;

: drag-slab ( world -- )
    drop ;

: start-drag-slab-rotation ( world -- )
    drop ;

: drag-slab-rotation ( world -- )
    drop ;

: start-drag-eye ( world -- )
    drop ;

: drag-eye ( world -- )
    drop ;

papier-world H{
    { T{ key-down f f "TAB" } [ stop-editing ] }
    { T{ button-down f f 1 }  [ start-drag-slab ] }
    { T{ drag f 1 }           [ drag-slab ] }
    { T{ button-down f f 2 }  [ start-drag-slab-rotation ] }
    { T{ drag f 2 }           [ drag-slab-rotation ] }
    { T{ button-down f f 3 }  [ start-drag-eye ] }
    { T{ drag f 3 }           [ drag-eye ] }
} set-gestures

M: papier-world tick-game-world
    dup focused?>> [ keyboard-input ] [ drop ] if ;

: order-slabs ( slabs eye -- slabs' )
    '[ center>> _ v- norm-sq ] inv-sort-with ; inline

: slab-vertices ( slab -- av at ac bv bt bc cv ct cc dv dt dc )
    [ matrix>> ] [ texcoords>> ] [ color>> ] tri {
        [ [ float-4{ -1 -1 0 1 } m4.v ] [                      ] [ ] tri* ]
        [ [ float-4{  1 -1 0 1 } m4.v ] [ { 2 1 0 3 } vshuffle ] [ ] tri* ]
        [ [ float-4{ -1  1 0 1 } m4.v ] [ { 0 3 2 1 } vshuffle ] [ ] tri* ]
        [ [ float-4{  1  1 0 1 } m4.v ] [ { 2 3 0 1 } vshuffle ] [ ] tri* ]
    } 3cleave ; inline

: slab-indexes ( i -- a b c d e f )
    4 * { [ ] [ 1 + ] [ 2 + ] [ 2 + ] [ 1 + ] [ 3 + ] } cleave ; inline

: render-slabs ( slabs -- vertices indexes )
    dup length iota [
        [ slab-vertices ]
        [ slab-indexes ] bi* 
    ] data-map( object object -- float-4[12] uint[6] ) ; inline

: render-slabs-to-buffers ( world -- )
    dup [ slabs>> ] [ uniforms>> eye>> ] bi order-slabs render-slabs
    [ [ vertex-buffer>> ] dip allocate-byte-array ]
    [ [ index-buffer>> ] dip allocate-byte-array ] bi-curry* bi ; inline

: slab-index-count ( world -- count )
    slabs>> length 6 * ; inline

M: papier-world draw-world*
    system-framebuffer { { default-attachment { 0.0 0.0 0.0 0.0 } } } clear-framebuffer

    dup render-slabs-to-buffers

    {
        { "primitive-mode" [ drop triangles-mode ] }
        { "indexes"        [
            [ index-buffer>> 0 <buffer-ptr> ] [ slab-index-count ] bi
            uint-indexes <index-elements>
        ] }
        { "uniforms"       [ uniforms>> ] }
        { "vertex-array"   [ vertex-array>> ] }
    } <render-set> render ;

M: papier-world resize-world
    [ uniforms>> ] [ <p-matrix> ] bi >>p_matrix drop ;

GAME: papier-game {
        { world-class papier-world }
        { title "Papier" }
        { pixel-format-attributes {
            windowed
            double-buffered
            T{ depth-bits { value 24 } }
        } }
        { use-game-input? t }
        { pref-dim { 1024 768 } }
        { tick-interval-micros $[ 60 fps ] }
    } ;
