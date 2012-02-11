//##############################################################################
//
// lbgpu_prime.cu
//
//  - Lattice Boltzmann
//
//  - D2Q9 / D3Q19
//
#include "flags.h"

#if DP_ON
typedef double real; // To be relocated (in flags.in?).
#else
typedef float real; // To be relocated (in flags.in?).
#endif

#ifdef __CUDACC__
real* f_mem_d;
int f_mem_size;
real* mv_mem_d;
int mv_mem_size;
unsigned char* solids_mem_d;
int solids_mem_size;
#endif

#include "lbgpu_prime.h"

int main( int argc, char **argv)
{


  int subs;
  int time, frame;

  struct lattice_struct *lattice;

  setbuf( stdout, (char*)NULL); // Don't buffer screen output.

#if VERBOSITY_LEVEL > 0
  printf("%s %d >> lbgpu_prime.c: main() -- Hello.\n", __FILE__, __LINE__);
#endif /* VERBOSITY_LEVEL > 0 */

  construct_lattice( &lattice, argc, argv);

  process_tic( lattice);

  init_problem( lattice);

  set_time( lattice, 0);
  set_frame( lattice, 0);

  output_frame( lattice);

  process_toc( lattice);
  display_etime( lattice);
  process_tic( lattice);

#ifdef __CUDACC__

  if( get_LX( lattice) % get_BX( lattice) != 0)
  {
    printf("\n%s %d ERROR: LX = %d must be divisible by BX = %d. (Exiting.)\n\n"
        , __FILE__
        , __LINE__
        , get_LX( lattice)
        , get_BX( lattice));
    process_exit(1);
  }
  if( get_LY( lattice) % get_BY( lattice) != 0)
  {
    printf("\n%s %d ERROR: LY = %d must be divisible by BY = %d. (Exiting.)\n\n"
        , __FILE__
        , __LINE__
        , get_LY( lattice)
        , get_BY( lattice));
    process_exit(1);
  }
  if( get_LZ( lattice) % get_BZ( lattice) != 0)
  {
    printf("\n%s %d ERROR: LX = %d must be divisible by BX = %d. (Exiting.)\n\n"
        , __FILE__
        , __LINE__
        , get_LZ( lattice)
        , get_BZ( lattice));
    process_exit(1);
  }


  dim3 blockDim( get_BX( lattice), get_BY( lattice), get_BZ( lattice));
  dim3 gridDim( get_LX( lattice) / get_BX( lattice),
      get_LY( lattice) / get_BY( lattice),
      get_LZ( lattice) / get_BZ( lattice) );

  cudaMemcpy( solids_mem_d + get_EndBoundSize( lattice)
      , get_solids_ptr(lattice, 0)
      , get_NumNodes( lattice)*sizeof(unsigned char)
      , cudaMemcpyHostToDevice);

  checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

  // Do boundary swap for solids.  This only needs to be done
  // once, of course.

#if PARALLEL
  // We'll want something involving the MPI buffers here.

  solid_send_recv_begin( lattice, 0);
  solid_send_recv_end( lattice, 0);

  // North / Top end
  cudaMemcpy( solids_mem_d + get_EndBoundSize( lattice) + get_NumNodes( lattice)
      , lattice->process.neg_dir_solid_to_recv
      , get_EndBoundSize( lattice)*sizeof(unsigned char)
      , cudaMemcpyHostToDevice);

  checkCUDAError( __FILE__, __LINE__, "solid swap");

  // South / Bottom end
  cudaMemcpy( solids_mem_d
      , lattice->process.pos_dir_solid_to_recv
      , get_EndBoundSize( lattice)*sizeof(unsigned char)
      , cudaMemcpyHostToDevice);

  checkCUDAError( __FILE__, __LINE__, "solid swap");

#else   // if !(PARALLEL)
  // North / Top end
  cudaMemcpy( solids_mem_d + get_EndBoundSize( lattice) + get_NumNodes( lattice)
      , solids_mem_d + get_EndBoundSize( lattice)
      , get_EndBoundSize( lattice)*sizeof(unsigned char)
      , cudaMemcpyDeviceToDevice);

  checkCUDAError( __FILE__, __LINE__, "solid swap");

  // South / Bottom end
  cudaMemcpy( solids_mem_d
      , solids_mem_d + get_NumNodes( lattice)
      , get_EndBoundSize( lattice)*sizeof(unsigned char)
      , cudaMemcpyDeviceToDevice);

  checkCUDAError( __FILE__, __LINE__, "solid swap");
#endif  // if PARALLEL

  int dir;
#if 1
  for( subs = 0; subs < get_NumSubs( lattice); subs++)
  {
    // In the final version, the CPU arrays may well have
    // the same 'additional boundary' structure as the GPU
    // arrays, in which case a single memcpy can be performed.
    cudaMemcpy( f_mem_d + subs * cumul_stride[get_NumVelDirs( lattice)]
        , get_fptr(lattice, subs, 0,0,0, 0,0,0, 0)
        , get_NumNodes( lattice)
        *(get_NumUnboundDirs( lattice))
        *sizeof(real)
        , cudaMemcpyHostToDevice);

    checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

    for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir+=2)
    {

      cudaMemcpy( f_mem_d + cumul_stride[dir]
          + subs * cumul_stride[get_NumVelDirs( lattice)]
          , get_fptr(lattice, subs, 0,0,0, 0,0,0, dir)
          , 2*get_NumNodes( lattice)
          *sizeof(real)
          , cudaMemcpyHostToDevice);

      checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");
    }


    cudaMemcpy( mv_mem_d + subs*get_NumNodes( lattice)*(1 + get_NumDims( lattice))
        , get_rho_ptr(lattice, subs, 0)
        , (1. + get_NumDims( lattice))
        *get_NumNodes( lattice)
        *sizeof(real)
        , cudaMemcpyHostToDevice);

    checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

  }
#endif
  int temp_frame_switch = 0;
  cudaMemcpyToSymbol( is_end_of_frame_mem_c, &temp_frame_switch, sizeof(int));

#if TEXTURE_FETCH
  cudaBindTexture(0, tex_solid, solids_mem_d);
#endif

#endif  // ifdef __CUDACC__


  cudaEvent_t start, stop;
  real timertime;
  real totaltime = 0.;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
#if 1
  for( frame = 0, time=1; time<=get_NumTimeSteps( lattice); time++)
  {
    set_time( lattice, time);

    // Do boundary swaps. The direction depends on
    // whether time is even or odd. Here, time is odd.
#if PARALLEL
    for( subs = 0; subs < get_NumSubs( lattice); subs++)
    {
#ifdef __CUDACC__
      //#if !(PAGE_LOCKED)

      cudaEventRecord(start,0);
      for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir++)
      {
        pdf_boundary_parallel( lattice, f_mem_d, cumul_stride
            , subs, dir, time, DEVICE_TO_HOST);
      }
      cudaEventRecord(stop, 0);
      cudaEventSynchronize(stop);
      cudaEventElapsedTime(&timertime,start,stop);
      totaltime += timertime;
      //#endif
#endif

      process_send_recv_begin( lattice, subs);
      process_send_recv_end(lattice, subs);

#ifdef __CUDACC__
      //#if !(PAGE_LOCKED)
      cudaEventRecord(start,0);
      for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir++)
      {
        pdf_boundary_parallel( lattice, f_mem_d, cumul_stride
            , subs, dir, time, HOST_TO_DEVICE);
      }
      cudaEventRecord(stop, 0);
      cudaEventSynchronize(stop);
      cudaEventElapsedTime(&timertime,start,stop);
      totaltime += timertime;

      //#endif
#endif
    }
#else   // if !(PARALLEL)
#ifdef __CUDACC__
    for( subs = 0; subs < get_NumSubs( lattice); subs++)
    {
      for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir++)
      {
        pdf_boundary_swap( lattice, f_mem_d, cumul_stride
            , subs, dir, time);
      }
    }
#endif
#endif  // if (PARALLEL)


    // Time steps are combined in a somewhat awkward way in order to minimize
    // the amount of temporary storage required and to allow the nodes to
    // be updated independently of neighbor nodes. This facilitates an
    // efficient GPU implementation.
    //
    // c.f., Bailey, Myre, Walsh et. al., Accelerating Lattice Boltzmann Fluid
    // Flow Simulations using Graphics Processors, ICPP 2009.
    // http://www.tc.umn.edu/~bail0253/

#ifdef __CUDACC__
    k_stream_collide_stream
      <<<
      gridDim
      , blockDim
      , sizeof(real)*( get_NumVelDirs( lattice)
          + get_NumDims( lattice)+1 )
      * get_BX( lattice)
      * get_BY( lattice)
      * get_BZ( lattice)
      >>>( f_mem_d, mv_mem_d, solids_mem_d
         );

    cudaThreadSynchronize();
    checkCUDAError( __FILE__, __LINE__, "k_stream_collide_stream");

    if( temp_frame_switch)
    {
      output_frame( lattice);
      temp_frame_switch = 0;
      cudaMemcpyToSymbol( is_end_of_frame_mem_c, &temp_frame_switch, sizeof(int));
    }
#else   // ifndef __CUDACC__
    stream_collide_stream( lattice);
#endif  // ifdef __CUDACC__

    set_time( lattice, ++time);

    // Do boundary swaps. The direction depends on
    // whether time is even or odd. Here, time is odd.
#if PARALLEL
    for( subs = 0; subs < get_NumSubs( lattice); subs++)
    {
#ifdef __CUDACC__
      //#if !(PAGE_LOCKED)
      cudaEventRecord(start, 0);
      for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir++)
      {
        pdf_boundary_parallel( lattice, f_mem_d, cumul_stride
            , subs, dir, time, DEVICE_TO_HOST);
      }
      cudaEventRecord(stop, 0);
      cudaEventSynchronize(stop);
      cudaEventElapsedTime(&timertime,start,stop);
      totaltime += timertime;

      //#endif
#endif

      process_send_recv_begin( lattice, subs);
      process_send_recv_end(lattice, subs);

#ifdef __CUDACC__
      //#if !(PAGE_LOCKED)
      cudaEventRecord(start, 0);
      for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir++)
      {
        pdf_boundary_parallel( lattice, f_mem_d, cumul_stride
            , subs, dir, time, HOST_TO_DEVICE);
      }
      cudaEventRecord(stop, 0);
      cudaEventSynchronize(stop);
      cudaEventElapsedTime(&timertime,start,stop);
      totaltime += timertime;

      //#endif
#endif
    }
#else   // if !(PARALLEL)
#ifdef __CUDACC__
    for( subs = 0; subs < get_NumSubs( lattice); subs++)
    {
      for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir++)
      {
        pdf_boundary_swap( lattice, f_mem_d, cumul_stride
            , subs, dir, time);
      }
    }
#endif
#endif  // if PARALLEL

#ifdef __CUDACC__
    if( is_end_of_frame(lattice,time))
    {
      temp_frame_switch = 1;
      cudaMemcpyToSymbol( is_end_of_frame_mem_c, &temp_frame_switch, sizeof(int));
    }

    k_collide
      <<<
      gridDim
      , blockDim
      , sizeof(real)*( get_NumVelDirs( lattice)
          + get_NumDims( lattice)+1 )
      * get_BX( lattice)
      * get_BY( lattice)
      * get_BZ( lattice)
      >>>( f_mem_d, mv_mem_d, solids_mem_d);
    cudaThreadSynchronize();
    checkCUDAError( __FILE__, __LINE__, "k_collide");
#else   // ifndef __CUDACC__
    collide( lattice);
#endif  // ifdef __CUDACC__

    if( is_end_of_frame(lattice,time))
    { 
      // Although it is necessary to copy device arrays to host at this point,
      // it is inefficient to write them to file here. Rather, we write to file
      // immediately after the first kernel, to allow concurrent host and
      // device execution.  On the last frame of course, it is necessary to
      // write to file here.
      set_frame( lattice, ++frame);

#ifdef __CUDACC__
      for( subs = 0; subs < get_NumSubs( lattice); subs++)
      {
        printf("Transferring subs %d "
            "macrovars from device to host for output. \n", subs);
        cudaMemcpy( get_rho_ptr(lattice, subs, 0)
            , mv_mem_d
            + subs*get_NumNodes( lattice)*( 1 + get_NumDims( lattice))
            + 0*get_NumNodes( lattice)
            , get_NumNodes( lattice)*sizeof(real)
            , cudaMemcpyDeviceToHost);
        checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

        cudaMemcpy( get_ux_ptr(lattice, subs, 0)
            , mv_mem_d
            + subs*get_NumNodes( lattice)*( 1 + get_NumDims( lattice))
            + 1*get_NumNodes( lattice)
            , get_NumNodes( lattice)*sizeof(real)
            , cudaMemcpyDeviceToHost);
        checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

        cudaMemcpy( get_uy_ptr(lattice, subs, 0)
            , mv_mem_d
            + subs*get_NumNodes( lattice)*( 1 + get_NumDims( lattice))
            + 2*get_NumNodes( lattice)
            , get_NumNodes( lattice)*sizeof(real)
            , cudaMemcpyDeviceToHost);
        checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

        if(get_NumDims( lattice) == 3)
        {
          cudaMemcpy( get_uz_ptr(lattice, subs, 0)
              , mv_mem_d
              + subs*get_NumNodes( lattice)*( 1 + get_NumDims( lattice))
              + 3*get_NumNodes( lattice)
              , get_NumNodes( lattice)*sizeof(real)
              , cudaMemcpyDeviceToHost);
          checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

        }
        if( do_write_f_txt_file( lattice))
        {  
          // In the final version, the CPU arrays may well have
          // the same 'additional boundary' structure as the GPU
          // arrays, in which case a single memcpy can be performed.
          cudaMemcpy( get_fptr(lattice, subs, 0,0,0, 0,0,0, 0)
              , f_mem_d + subs * cumul_stride[get_NumVelDirs( lattice)]
              , get_NumNodes( lattice)
              *(get_NumUnboundDirs( lattice))
              *sizeof(real)
              , cudaMemcpyDeviceToHost);

          checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");

          for( dir=get_NumUnboundDirs( lattice); dir < get_NumVelDirs( lattice); dir+=2)
          {

            cudaMemcpy( get_fptr(lattice, subs, 0,0,0, 0,0,0, dir)
                , f_mem_d + cumul_stride[dir]
                + subs * cumul_stride[get_NumVelDirs( lattice)]
                , 2*get_NumNodes( lattice)
                *sizeof(real)
                , cudaMemcpyDeviceToHost);

            checkCUDAError( __FILE__, __LINE__, "cudaMemcpy");
          }
        }
      }
#endif  // ifdef __CUDACC__
      if( frame == get_NumFrames( lattice))
      {
        output_frame( lattice);
      }
      process_toc( lattice);
      display_etime( lattice);

#ifdef __CUDACC__
      printf("**************\n");
      printf("  __CUDACC__\n");
      printf("**************\n");
#endif
    }

  } /* for( time=1; time<=lattice->NumTimeSteps; time++) */
#endif

  process_barrier();
  process_toc( lattice);
  display_etime( lattice);

  destruct_lattice( lattice);

#if VERBOSITY_LEVEL > 0
  printf("\n");
  printf("%s %d >> lbgpu_prime.c: main() -- Terminating normally.\n",
      __FILE__, __LINE__);
  printf("\n");
#endif /* VERBOSITY_LEVEL > 0 */

  printf(" \n\n\n Time taken for loop is %f \n\n", totaltime);
  return 0;

} /* int main( int argc, char **argv) */
