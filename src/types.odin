package mou

import gl "vendor:OpenGL"

Data_Type :: enum i32 {
	Byte                                      = gl.BYTE,
	Unsigned_Byte                             = gl.UNSIGNED_BYTE,
	Short                                     = gl.SHORT,
	Unsigned_Short                            = gl.UNSIGNED_SHORT,
	Int                                       = gl.INT,
	Unsigned_Int                              = gl.UNSIGNED_INT,
	Float                                     = gl.FLOAT,
	Float_Vec2                                = gl.FLOAT_VEC2,
	Float_Vec3                                = gl.FLOAT_VEC3,
	Float_Vec4                                = gl.FLOAT_VEC4,
	Int_Vec2                                  = gl.INT_VEC2,
	Int_Vec3                                  = gl.INT_VEC3,
	Int_Vec4                                  = gl.INT_VEC4,
	Bool                                      = gl.BOOL,
	Bool_Vec2                                 = gl.BOOL_VEC2,
	Bool_Vec3                                 = gl.BOOL_VEC3,
	Bool_Vec4                                 = gl.BOOL_VEC4,
	Float_Mat2                                = gl.FLOAT_MAT2,
	Float_Mat3                                = gl.FLOAT_MAT3,
	Float_Mat4                                = gl.FLOAT_MAT4,
	Sampler_1D_Array                          = gl.SAMPLER_1D_ARRAY,
	Sampler_2D_Array                          = gl.SAMPLER_2D_ARRAY,
	Sampler_1D_Array_Shadow                   = gl.SAMPLER_1D_ARRAY_SHADOW,
	Sampler_2D_Array_Shadow                   = gl.SAMPLER_2D_ARRAY_SHADOW,
	Sampler_Cube_Shadow                       = gl.SAMPLER_CUBE_SHADOW,
	Sampler_1D                                = gl.SAMPLER_1D,
	Sampler_2D                                = gl.SAMPLER_2D,
	Sampler_3D                                = gl.SAMPLER_3D,
	Sampler_Cube                              = gl.SAMPLER_CUBE,
	Sampler_1D_Shadow                         = gl.SAMPLER_1D_SHADOW,
	Sampler_2D_Shadow                         = gl.SAMPLER_2D_SHADOW,
	Double                                    = gl.DOUBLE,
	Double_Vec2                               = gl.DOUBLE_VEC2,
	Double_Vec3                               = gl.DOUBLE_VEC3,
	Double_Vec4                               = gl.DOUBLE_VEC4,
	Double_Mat2                               = gl.DOUBLE_MAT2,
	Double_Mat3                               = gl.DOUBLE_MAT3,
	Double_Mat4                               = gl.DOUBLE_MAT4,
	Double_Mat2x3                             = gl.DOUBLE_MAT2x3,
	Double_Mat2x4                             = gl.DOUBLE_MAT2x4,
	Double_Mat3x2                             = gl.DOUBLE_MAT3x2,
	Double_Mat3x4                             = gl.DOUBLE_MAT3x4,
	Double_Mat4x2                             = gl.DOUBLE_MAT4x2,
	Double_Mat4x3                             = gl.DOUBLE_MAT4x3,
	Unsigned_Int_Vec2                         = gl.UNSIGNED_INT_VEC2,
	Unsigned_Int_Vec3                         = gl.UNSIGNED_INT_VEC3,
	Unsigned_Int_Vec4                         = gl.UNSIGNED_INT_VEC4,
	Int_Sampler_1D                            = gl.INT_SAMPLER_1D,
	Int_Sampler_2D                            = gl.INT_SAMPLER_2D,
	Int_Sampler_3D                            = gl.INT_SAMPLER_3D,
	Int_Sampler_Cube                          = gl.INT_SAMPLER_CUBE,
	Int_Sampler_1D_Array                      = gl.INT_SAMPLER_1D_ARRAY,
	Int_Sampler_2D_Array                      = gl.INT_SAMPLER_2D_ARRAY,
	Unsigned_Int_Sampler_1D                   = gl.UNSIGNED_INT_SAMPLER_1D,
	Unsigned_Int_Sampler_2D                   = gl.UNSIGNED_INT_SAMPLER_2D,
	Unsigned_Int_Sampler_3D                   = gl.UNSIGNED_INT_SAMPLER_3D,
	Unsigned_Int_Sampler_Cube                 = gl.UNSIGNED_INT_SAMPLER_CUBE,
	Unsigned_Int_Sampler_1D_Array             = gl.UNSIGNED_INT_SAMPLER_1D_ARRAY,
	Unsigned_Int_Sampler_2D_Array             = gl.UNSIGNED_INT_SAMPLER_2D_ARRAY,
	Texture_2D_Multisample                    = gl.TEXTURE_2D_MULTISAMPLE,
	Proxy_Texture_2D_Multisample              = gl.PROXY_TEXTURE_2D_MULTISAMPLE,
	Texture_2D_Multisample_Array              = gl.TEXTURE_2D_MULTISAMPLE_ARRAY,
	Proxy_Texture_2D_Multisample_Array        = gl.PROXY_TEXTURE_2D_MULTISAMPLE_ARRAY,
	Texture_Binding_2D_Multisample            = gl.TEXTURE_BINDING_2D_MULTISAMPLE,
	Texture_Binding_2D_Multisample_Array      = gl.TEXTURE_BINDING_2D_MULTISAMPLE_ARRAY,
	Texture_Samples                           = gl.TEXTURE_SAMPLES,
	Texture_Fixed_Sample_Locations            = gl.TEXTURE_FIXED_SAMPLE_LOCATIONS,
	Sampler_2D_Multisample                    = gl.SAMPLER_2D_MULTISAMPLE,
	Int_Sampler_2D_Multisample                = gl.INT_SAMPLER_2D_MULTISAMPLE,
	Unsigned_Int_Sampler_2D_Multisample       = gl.UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE,
	Sampler_2D_Multisample_Array              = gl.SAMPLER_2D_MULTISAMPLE_ARRAY,
	Int_Sampler_2D_Multisample_Array          = gl.INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
	Unsigned_Int_Sampler_2D_Multisample_Array = gl.UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
	Image_1D                                  = gl.IMAGE_1D,
	Image_2D                                  = gl.IMAGE_2D,
	Image_3D                                  = gl.IMAGE_3D,
	Image_2D_Rect                             = gl.IMAGE_2D_RECT,
	Image_Cube                                = gl.IMAGE_CUBE,
	Image_Buffer                              = gl.IMAGE_BUFFER,
	Image_1D_Array                            = gl.IMAGE_1D_ARRAY,
	Image_2D_Array                            = gl.IMAGE_2D_ARRAY,
	Image_Cube_Map_Array                      = gl.IMAGE_CUBE_MAP_ARRAY,
	Image_2D_Multisample                      = gl.IMAGE_2D_MULTISAMPLE,
	Image_2D_Multisample_Array                = gl.IMAGE_2D_MULTISAMPLE_ARRAY,
	Int_Image_1D                              = gl.INT_IMAGE_1D,
	Int_Image_2D                              = gl.INT_IMAGE_2D,
	Int_Image_3D                              = gl.INT_IMAGE_3D,
	Int_Image_2D_Rect                         = gl.INT_IMAGE_2D_RECT,
	Int_Image_Cube                            = gl.INT_IMAGE_CUBE,
	Int_Image_Buffer                          = gl.INT_IMAGE_BUFFER,
	Int_Image_1D_Array                        = gl.INT_IMAGE_1D_ARRAY,
	Int_Image_2D_Array                        = gl.INT_IMAGE_2D_ARRAY,
	Int_Image_Cube_Map_Array                  = gl.INT_IMAGE_CUBE_MAP_ARRAY,
	Int_Image_2D_Multisample                  = gl.INT_IMAGE_2D_MULTISAMPLE,
	Int_Image_2D_Multisample_Array            = gl.INT_IMAGE_2D_MULTISAMPLE_ARRAY,
	Unsigned_Int_Image_1D                     = gl.UNSIGNED_INT_IMAGE_1D,
	Unsigned_Int_Image_2D                     = gl.UNSIGNED_INT_IMAGE_2D,
	Unsigned_Int_Image_3D                     = gl.UNSIGNED_INT_IMAGE_3D,
	Unsigned_Int_Image_2D_Rect                = gl.UNSIGNED_INT_IMAGE_2D_RECT,
	Unsigned_Int_Image_Cube                   = gl.UNSIGNED_INT_IMAGE_CUBE,
	Unsigned_Int_Image_Buffer                 = gl.UNSIGNED_INT_IMAGE_BUFFER,
	Unsigned_Int_Image_1D_Array               = gl.UNSIGNED_INT_IMAGE_1D_ARRAY,
	Unsigned_Int_Image_2D_Array               = gl.UNSIGNED_INT_IMAGE_2D_ARRAY,
	Unsigned_Int_Image_Cube_Map_Array         = gl.UNSIGNED_INT_IMAGE_CUBE_MAP_ARRAY,
	Unsigned_Int_Image_2D_Multisample         = gl.UNSIGNED_INT_IMAGE_2D_MULTISAMPLE,
	Unsigned_Int_Image_2D_Multisample_Array   = gl.UNSIGNED_INT_IMAGE_2D_MULTISAMPLE_ARRAY,
	Unsigned_Int_Atomic_Counter               = gl.UNSIGNED_INT_ATOMIC_COUNTER,
}
