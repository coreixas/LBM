
__global__
void k_stream_collide_stream(
    real* f_mem_d
    , real* mv_mem_d
    , unsigned char* solids_mem_d
    , real* ns_mem_d
    )
{
  int i = threadIdx.x + blockIdx.x*blockDim.x;
  int j = threadIdx.y + blockIdx.y*blockDim.y;

  int a, subs, k, n, b;

  for( subs=0; subs<numsubs_c; subs++)
  {
#if (INAMURO_SIGMA_COMPONENT)
    if( subs != 1 || (time_c >= sigma_t_on_c && time_c <= sigma_t_off_c))
    {
#endif

#if __CUDA_ARCH__ < 200
      int klc;
      for( klc=0; klc < kloop_c; klc++)
      {
        k = threadIdx.z + klc*blockDim.z;
#else
        k = threadIdx.z + blockIdx.z*blockDim.z;
#endif

        n = i + j * ni_c + k * nixnj_c;

#if !(COMPUTE_ON_SOLIDS)
        if( d_is_not_solid( solids_mem_d, n + end_bound_c))
        {
#endif
          b = threadIdx.x + threadIdx.y*blockDim.x
            + threadIdx.z*bixbj_c;



          // Populate shared memory for a given node with global memory values from
          // surrounding nodes.  This is a streaming operation. Splitting to odd and
          // even parts is necessary for the boundary condition implementation.

          fptr[b] = get_f1d_d( f_mem_d, solids_mem_d, ns_mem_d
              , subs
              , i,j,k,n
              , -vx_c[0],-vy_c[0],-vz_c[0]
              , 0, 0);

          for( a=1; a<numdirs_c; a+=2)
          { 
            fptr[b + a*blocksize_c] = get_f1d_d( f_mem_d, solids_mem_d, ns_mem_d
                , subs
                , i,j,k,n
                , -vx_c[a],-vy_c[a],-vz_c[a]
                , a, 1);
          }
          for( a=2; a<numdirs_c; a+=2)
          { 
            fptr[b + a*blocksize_c] = get_f1d_d( f_mem_d, solids_mem_d, ns_mem_d
                , subs
                , i,j,k,n
                , -vx_c[a],-vy_c[a],-vz_c[a]
                , a, -1);
          }


#if INAMURO_SIGMA_COMPONENT 
          if( subs == 1)
          {
            // Initialize shared memory values for calculating rho.
            fptr[b + (numdirs_c+0)*blocksize_c] = fptr[b];

            // Note that the velocity macroscopic variables are already
            // set from substance 0, so we don't need to touch them

            // Calculate rho
            for( a=1; a<numdirs_c; a++)
            {
              fptr[b + (numdirs_c+0)*blocksize_c]
                += fptr[b + a*blocksize_c];
            }


          }
          else
          {
#endif  // INAMURO_SIGMA_COMPONENT


#if KAHAN_SUMMATION
            fk_add( fptr, b);
#else
            // Initialize shared memory values for calculating macro vars.
            fptr[b + (numdirs_c+0)*blocksize_c] = fptr[b];
            // Calculate macroscopic variables.


            for( a=1; a<numdirs_c; a++)
            {
              fptr[b + (numdirs_c+0)*blocksize_c]
                += fptr[b + a*blocksize_c];

              if( /*debug*/0)
              {
                fptr[b + (numdirs_c+0)*blocksize_c] = fptr[b+5*blocksize_c];
              }
            }
#endif

            if( numdims_c == 2)
            {
              fptr[b + (numdirs_c+1)*blocksize_c] = 0.;
              fptr[b + (numdirs_c+2)*blocksize_c] = 0.;

              //if( fptr[b + (numdirs_c+0)*blocksize_c] > EPSILON)
              //{
                for( a=0; a<numdirs_c; a++)
                {
                  fptr[b + (numdirs_c+1)*blocksize_c]
                    += ((real) vx_c[a])*fptr[b + a*blocksize_c];

                  fptr[b + (numdirs_c+2)*blocksize_c]
                    += ((real) vy_c[a])*fptr[b + a*blocksize_c];
                }

#if WALSH_NS_ON
                fptr[b + (numdirs_c+1)*blocksize_c] *=
                  (1. - ns_mem_d[n + end_bound_c]);

                fptr[b + (numdirs_c+2)*blocksize_c] *=
                  (1. - ns_mem_d[n + end_bound_c]);
#endif

                fptr[b + (numdirs_c+1)*blocksize_c] /=
#if COMPRESSIBLE
#if ACCURATE
                  ( rho_A_c[subs] + fptr[b + (numdirs_c+0)*blocksize_c]);
#else
                  ( fptr[b + (numdirs_c+0)*blocksize_c]);
#endif
#else
                  ( rho_A_c[subs]);
#endif

                fptr[b + (numdirs_c+2)*blocksize_c] /=
#if COMPRESSIBLE
#if ACCURATE
                  ( rho_A_c[subs] + fptr[b + (numdirs_c+0)*blocksize_c]);
#else
                  ( fptr[b + (numdirs_c+0)*blocksize_c]);
#endif
#else
                  ( rho_A_c[subs]);
#endif


              //}   //rho > EPSILON
            }
            else  // numdims_c == 3
            {
              fptr[b + (numdirs_c+1)*blocksize_c] = 0.;
              fptr[b + (numdirs_c+2)*blocksize_c] = 0.;
              fptr[b + (numdirs_c+3)*blocksize_c] = 0.;

              //if( fptr[b + (numdirs_c+0)*blocksize_c] > EPSILON)
              //{
                for( a=0; a<numdirs_c; a++)
                {
                  fptr[b + (numdirs_c+1)*blocksize_c]
                    += ((real) vx_c[a])*fptr[b + a*blocksize_c];

                  fptr[b + (numdirs_c+2)*blocksize_c]
                    += ((real) vy_c[a])*fptr[b + a*blocksize_c];

                  fptr[b + (numdirs_c+3)*blocksize_c]
                    += ((real) vz_c[a])*fptr[b + a*blocksize_c];

                }

#if WALSH_NS_ON
                fptr[b + (numdirs_c+1)*blocksize_c] *=
                  (1. - ns_mem_d[n + end_bound_c]);

                fptr[b + (numdirs_c+2)*blocksize_c] *=
                  (1. - ns_mem_d[n + end_bound_c]);

                fptr[b + (numdirs_c+3)*blocksize_c] *=
                  (1. - ns_mem_d[n + end_bound_c]);

#endif

                fptr[b + (numdirs_c+1)*blocksize_c] /=
#if COMPRESSIBLE
#if ACCURATE
                  ( rho_A_c[subs] + fptr[b + (numdirs_c+0)*blocksize_c]);
#else
                  ( fptr[b + (numdirs_c+0)*blocksize_c]);
#endif
#else
                  ( rho_A_c[subs]);
#endif


                fptr[b + (numdirs_c+2)*blocksize_c] /=
#if COMPRESSIBLE
#if ACCURATE
                  ( rho_A_c[subs] + fptr[b + (numdirs_c+0)*blocksize_c]);
#else
                  ( fptr[b + (numdirs_c+0)*blocksize_c]);
#endif
#else
                  ( rho_A_c[subs]);
#endif


                fptr[b + (numdirs_c+3)*blocksize_c] /=
#if COMPRESSIBLE
#if ACCURATE
                  ( rho_A_c[subs] + fptr[b + (numdirs_c+0)*blocksize_c]);
#else
                  ( fptr[b + (numdirs_c+0)*blocksize_c]);
#endif
#else
                  ( rho_A_c[subs]);
#endif



              //}   //rho > EPSILON
            }     // numdims_c == 2

#if INAMURO_SIGMA_COMPONENT
        }
#endif  // INAMURO_SIGMA_COMPONENT
          
          if( !d_skip_body_force_term())
          {
            // Modify macroscopic variables with a body force
#if INAMURO_SIGMA_COMPONENT
            if( subs != 1)
            {
#endif
              for( a=1; a<=numdims_c; a++)
              {
                apply_accel_mv( subs, a, b, n, fptr, ns_mem_d);
              }
#if INAMURO_SIGMA_COMPONENT
            }
            else
            {
              fptr[b + (numdirs_c+0)*blocksize_c]
                *= (1.0 - sink_c * tau_c[1]);

            }
#endif

          }
          
          if( is_end_of_frame_mem_c)
          {
#if INAMURO_SIGMA_COMPONENT
            if( subs == 0)
            {
              set_mv_d( mv_mem_d
                  , subs, n, 0
                  , fptr[ b + (numdirs_c + 0)*blocksize_c]
#if ACCURATE
                  + rho_A_c[subs]
#endif
                  );
            }
            else
            {
              set_mv_d( mv_mem_d
                  , subs, n, 0
                  , fptr[ b + (numdirs_c + 0)*blocksize_c] );
            }
#else
            set_mv_d( mv_mem_d
                , subs, n, 0
                  , fptr[ b + (numdirs_c + 0)*blocksize_c]
#if ACCURATE
                  + rho_A_c[subs]
#endif
                  );

#endif

            // Store macroscopic variables in global memory.
            for( a=1; a<=numdims_c; a++)
            {
              set_mv_d( mv_mem_d
                  , subs, n, a
                  , fptr[ b + (numdirs_c + a)*blocksize_c] );

              if( /*debug*/0)
              {
                set_mv_d( mv_mem_d, subs, n, a, pfmul_c);
              }
            }
          }
          else
          {
            if( pest_output_flag_c)
            {
              if( subs == 0)
              {    
                set_mv_d( mv_mem_d
                    , subs, n, 1
                    , fptr[ b + (numdirs_c + 1)*blocksize_c] );

                set_mv_d( mv_mem_d
                    , subs, n, 2
                    , fptr[ b + (numdirs_c + 2)*blocksize_c] );

                if( numdims_c == 3)
                {
                  set_mv_d( mv_mem_d
                      , subs, n, 3
                      , fptr[ b + (numdirs_c + 3)*blocksize_c] );
                }
              }
              else
              {
                set_mv_d( mv_mem_d
                    , subs, n, 0
                    , fptr[ b + (numdirs_c + 0)*blocksize_c] );

              }
            }
          }

          if( !d_skip_collision_step())
          {

            // Calculate u-squared since it is used many times
            real usq;

#if INAMURO_SIGMA_COMPONENT
            if( subs != 1)
            {
#endif
              usq = fptr[b + (numdirs_c+1)*blocksize_c]
                * fptr[b + (numdirs_c+1)*blocksize_c]

                + fptr[b + (numdirs_c+2)*blocksize_c]
                * fptr[b + (numdirs_c+2)*blocksize_c];

              if( numdims_c==3)
              {
                usq += fptr[b + (numdirs_c+3)*blocksize_c]
                  * fptr[b + (numdirs_c+3)*blocksize_c];
              }
#if INAMURO_SIGMA_COMPONENT
            }
#endif
            // Calculate the collision operator and add to f resulting from first
            // streaming (TODO: Why do we pass f_mem_d to this function?)

#if WALSH_NS_ON
            real temp1, temp2;

            temp1 = fptr[b];
            calc_f_tilde_d( subs, 0, b, n, fptr, usq);
            fptr[b] *= 1. - ns_mem_d[ n + end_bound_c];
            fptr[b] += ns_mem_d[ n + end_bound_c] * temp1;

            for( a=1; a<numdirs_c; a+=2)
            {
              temp1 = fptr[b + a*blocksize_c];
              temp2 = fptr[b + (a+1)*blocksize_c];
              calc_f_tilde_d( subs, a, b, n, fptr, usq);
              calc_f_tilde_d( subs, a+1, b, n, fptr, usq);

              fptr[b + a*blocksize_c] *= 1. - ns_mem_d[ n + end_bound_c];
              fptr[b + a*blocksize_c] += ns_mem_d[ n + end_bound_c] * temp2;
              fptr[b + (a+1)*blocksize_c] *= 1. - ns_mem_d[ n + end_bound_c];
              fptr[b + (a+1)*blocksize_c] += ns_mem_d[ n + end_bound_c] * temp1;

            }

#else
            for( a=0; a<numdirs_c; a++)
            {
              calc_f_tilde_d( subs, a, b, n, fptr, usq);
            }
#endif
          }

          // Finally, save results back to global memory in adjacent nodes.  This is
          // a second streaming operation.  Note that the 'swap' that occurs in the
          // CPU code is combined with this operation without penalty.  This utilizes
          // the rearrangement of the v vectors into opposite pairs.
          // Populate shared memory for a given node with global memory values from
          // surrounding nodes.  This is a streaming operation. Splitting to odd and
          // even parts is necessary for the boundary condition implementation.

          set_f1d_d( f_mem_d, solids_mem_d, ns_mem_d
              , subs
              , i,j,k,n
              , vx_c[0],vy_c[0],vz_c[0]
              , 0, 0, fptr[b + 0*blocksize_c]);

          for( a=1; a<numdirs_c; a+=2)
          {
            set_f1d_d( f_mem_d, solids_mem_d, ns_mem_d
                , subs
                , i,j,k,n
                , vx_c[a],vy_c[a],vz_c[a]
                , a, 1, fptr[b + a*blocksize_c]);
          }

          for( a=2; a<numdirs_c; a+=2)
          {
            set_f1d_d( f_mem_d, solids_mem_d, ns_mem_d
                , subs
                , i,j,k,n
                , vx_c[a],vy_c[a],vz_c[a]
                , a, -1, fptr[b + a*blocksize_c]);
          }

#if !(COMPUTE_ON_SOLIDS)
        }
#endif


#if __CUDA_ARCH__ < 200
      }  /*for( klc=0; klc < kloop_c; klc++)*/
#endif

#if (INAMURO_SIGMA_COMPONENT)
    }       // if( subs!=1)
#endif


  }  /* subs loop */


}
