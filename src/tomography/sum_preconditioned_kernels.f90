!=====================================================================
!
!               S p e c f e m 3 D  V e r s i o n  2 . 1
!               ---------------------------------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                        Princeton University, USA
!                and CNRS / University of Marseille, France
!                 (there are currently many more authors!)
! (c) Princeton University and CNRS / University of Marseille, July 2012
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
!=====================================================================


! sum_preconditioned_kernels
!
! this program can be used for event kernel summation,
! where it sums up transverse isotropic kernel files:
!
!   - proc***_reg1_bulk_c_kernel.bin
!   - proc***_reg1_bulk_betav_kernel.bin
!   - proc***_reg1_bulk_betah_kernel.bin
!   - proc***_reg1_eta_kernel.bin
!
! this version uses the approximate Hessian stored as
!   - proc***_reg1_hess_kernel.bin
!          to precondition the transverse isotropic kernel files
!
! input file: kernels_list.txt
!   lists all event kernel directories which should be summed together
!
! input directory:  INPUT_KERNELS/
!    contains links to all event kernel directories (listed in "kernels_list.txt")
!
! output directory: OUTPUT_SUM/
!    the resulting kernel files will be stored in this directory


program sum_preconditioned_kernels

  use tomography_par,only: MAX_STRING_LEN,MAX_NUM_NODES,KERNEL_FILE_LIST,IIN, &
    myrank,sizeprocs, &
    NGLOB,NSPEC, &
    USE_ALPHA_BETA_RHO,USE_ISO_KERNELS

  implicit none

  character(len=MAX_STRING_LEN) :: kernel_list(MAX_NUM_NODES)
  character(len=MAX_STRING_LEN) :: sline, kernel_name,prname_lp
  integer :: nker
  integer :: ier

  double precision :: DT
  double precision :: HDUR_MOVIE,OLSEN_ATTENUATION_RATIO,f0_FOR_PML
  integer :: NPROC,NTSTEP_BETWEEN_OUTPUT_SEISMOS,NSTEP, &
            UTM_PROJECTION_ZONE,SIMULATION_TYPE,NGNOD,NGNOD2D
  integer :: NSOURCES,NTSTEP_BETWEEN_READ_ADJSRC,NOISE_TOMOGRAPHY,EXTERNAL_CODE_TYPE
  integer :: NTSTEP_BETWEEN_FRAMES,NTSTEP_BETWEEN_OUTPUT_INFO
  integer :: MOVIE_TYPE,IMODEL
  logical :: MOVIE_SURFACE,MOVIE_VOLUME,CREATE_SHAKEMAP,SAVE_DISPLACEMENT, &
            USE_HIGHRES_FOR_MOVIES,SUPPRESS_UTM_PROJECTION
  logical :: ATTENUATION,USE_OLSEN_ATTENUATION, &
            APPROXIMATE_OCEAN_LOAD,TOPOGRAPHY,USE_FORCE_POINT_SOURCE
  logical :: STACEY_ABSORBING_CONDITIONS,SAVE_FORWARD,STACEY_INSTEAD_OF_FREE_SURFACE
  logical :: ANISOTROPY,SAVE_MESH_FILES,USE_RICKER_TIME_FUNCTION,PRINT_SOURCE_TIME_FUNCTION
  logical :: PML_CONDITIONS,PML_INSTEAD_OF_FREE_SURFACE,FULL_ATTENUATION_SOLID, &
             COUPLE_WITH_EXTERNAL_CODE,MESH_A_CHUNK_OF_THE_EARTH
  character(len=MAX_STRING_LEN) :: LOCAL_PATH,TOMOGRAPHY_PATH,TRACTION_PATH,SEP_MODEL_DIRECTORY

  ! ============ program starts here =====================
  ! initialize the MPI communicator and start the NPROCTOT MPI processes
  call init_mpi()
  call world_size(sizeprocs)
  call world_rank(myrank)

  if (myrank==0) then
    write(*,*) 'sum_preconditioned_kernels:'
    write(*,*)
    write(*,*) 'reading kernel list: '
  endif
  call synchronize_all()

  ! reads in event list
  nker=0
  open(unit = IIN, file = trim(KERNEL_FILE_LIST), status = 'old',iostat = ier)
  if (ier /= 0) then
     print *,'Error opening ',trim(KERNEL_FILE_LIST),myrank
     stop 1
  endif
  do while (1 == 1)
     read(IIN,'(a)',iostat=ier) sline
     if (ier /= 0) exit
     nker = nker+1
     if (nker > MAX_NUM_NODES) stop 'Error number of kernels exceeds MAX_NUM_NODES'
     kernel_list(nker) = sline
  enddo
  close(IIN)
  if (myrank == 0) then
    write(*,*) '  ',nker,' events'
    write(*,*)
  endif

  ! needs local_path for mesh files
  call read_parameter_file(NPROC,NTSTEP_BETWEEN_OUTPUT_SEISMOS,NSTEP,DT,NGNOD,NGNOD2D, &
                           UTM_PROJECTION_ZONE,SUPPRESS_UTM_PROJECTION,TOMOGRAPHY_PATH, &
                           ATTENUATION,USE_OLSEN_ATTENUATION,LOCAL_PATH,NSOURCES, &
                           APPROXIMATE_OCEAN_LOAD,TOPOGRAPHY,ANISOTROPY,STACEY_ABSORBING_CONDITIONS,MOVIE_TYPE, &
                           MOVIE_SURFACE,MOVIE_VOLUME,CREATE_SHAKEMAP,SAVE_DISPLACEMENT, &
                           NTSTEP_BETWEEN_FRAMES,USE_HIGHRES_FOR_MOVIES,HDUR_MOVIE, &
                           SAVE_MESH_FILES,PRINT_SOURCE_TIME_FUNCTION, &
                           NTSTEP_BETWEEN_OUTPUT_INFO,SIMULATION_TYPE,SAVE_FORWARD, &
                           NTSTEP_BETWEEN_READ_ADJSRC,NOISE_TOMOGRAPHY, &
                           USE_FORCE_POINT_SOURCE,STACEY_INSTEAD_OF_FREE_SURFACE, &
                           USE_RICKER_TIME_FUNCTION,OLSEN_ATTENUATION_RATIO,PML_CONDITIONS, &
                           PML_INSTEAD_OF_FREE_SURFACE,f0_FOR_PML,IMODEL,SEP_MODEL_DIRECTORY, &
                           FULL_ATTENUATION_SOLID,TRACTION_PATH,COUPLE_WITH_EXTERNAL_CODE,EXTERNAL_CODE_TYPE, &
                           MESH_A_CHUNK_OF_THE_EARTH)

  ! checks if number of MPI process as specified
  if (sizeprocs /= NPROC) then
    if (myrank == 0) then
      print*,''
      print*,'Error: run xsum_kernels with the same number of MPI processes '
      print*,'       as specified in Par_file by NPROC when slices were created'
      print*,''
      print*,'for example: mpirun -np ',NPROC,' ./xsum_kernels ...'
      print*,''
    endif
    call synchronize_all()
    stop 'Error total number of slices'
  endif
  call synchronize_all()

  ! reads mesh file
  !
  ! needs to get array dimensions

  ! opens external mesh file
  write(prname_lp,'(a,i6.6,a)') trim(LOCAL_PATH)//'/proc',myrank,'_'//'external_mesh.bin'
  open(unit=27,file=trim(prname_lp),&
          status='old',action='read',form='unformatted',iostat=ier)
  if (ier /= 0) then
    print*,'Error: could not open database '
    print*,'path: ',trim(prname_lp)
    stop 'Error reading external mesh file'
  endif

  ! gets number of elements and global points for this partition
  read(27) NSPEC
  read(27) NGLOB

  close(27)

  ! user output
  if (myrank == 0) then
    print*,'summing kernels in INPUT_KERNELS/ directories:'
    print*,kernel_list(1:nker)
    print*
  endif

  ! synchronizes
  call synchronize_all()

  ! sums up kernels
  if (USE_ISO_KERNELS) then

    !  isotropic kernels
    if (myrank == 0) write(*,*) 'isotropic kernels: bulk_c, bulk_beta, rho'

    kernel_name = 'bulk_c_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'bulk_beta_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'rho_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

  else if (USE_ALPHA_BETA_RHO) then

    ! isotropic kernels
    if (myrank == 0) write(*,*) 'isotropic kernels: alpha, beta, rho'

    kernel_name = 'alpha_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'beta_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'rho_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

  else

    ! transverse isotropic kernels
    if (myrank == 0) write(*,*) 'transverse isotropic kernels: bulk_c, bulk_betav, bulk_betah,eta'

    kernel_name = 'bulk_c_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'bulk_betav_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'bulk_betah_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

    kernel_name = 'eta_kernel'
    call sum_kernel_pre(kernel_name,kernel_list,nker)

  endif

  if (myrank==0) write(*,*) 'done writing all kernels, see directory OUTPUT_SUM/'

  ! stop all the processes, and exit
  call finalize_mpi()

end program sum_preconditioned_kernels

!
!-------------------------------------------------------------------------------------------------
!

subroutine sum_kernel_pre(kernel_name,kernel_list,nker)

  use tomography_par

  implicit none

  character(len=MAX_STRING_LEN) :: kernel_name,kernel_list(MAX_NUM_NODES)
  integer :: nker

  ! local parameters
  character(len=MAX_STRING_LEN*2) :: k_file
  real(kind=CUSTOM_REAL), dimension(:,:,:,:),allocatable :: kernel,hess,total_kernel
  double precision :: norm,norm_sum
  integer :: iker,ier
  real(kind=CUSTOM_REAL), dimension(:,:,:,:),allocatable :: total_hess,mask_source

  ! initializes arrays
  allocate(kernel(NGLLX,NGLLY,NGLLZ,NSPEC), &
           hess(NGLLX,NGLLY,NGLLZ,NSPEC), &
           total_kernel(NGLLX,NGLLY,NGLLZ,NSPEC),stat=ier)
  if (ier /= 0) stop 'Error allocating kernel arrays'

  if (USE_HESS_SUM) then
    allocate( total_hess(NGLLX,NGLLY,NGLLZ,NSPEC) )
    total_hess(:,:,:,:) = 0.0_CUSTOM_REAL
  endif

  if (USE_SOURCE_MASK) then
    allocate( mask_source(NGLLX,NGLLY,NGLLZ,NSPEC) )
    mask_source(:,:,:,:) = 1.0_CUSTOM_REAL
  endif

  ! loops over all event kernels
  total_kernel = 0._CUSTOM_REAL
  do iker = 1, nker
    ! user output
    if (myrank==0) then
      write(*,*) 'reading in event kernel for: ',trim(kernel_name)
      write(*,*) 'and preconditioner         : ','hess_kernel'
      write(*,*) '    ',iker, ' out of ', nker
    endif

    ! sensitivity kernel / frechet derivative
    kernel = 0._CUSTOM_REAL
    write(k_file,'(a,i6.6,a)') 'INPUT_KERNELS/'//trim(kernel_list(iker)) &
                          //'/proc',myrank,trim(REG)//trim(kernel_name)//'.bin'

    open(IIN,file=trim(k_file),status='old',form='unformatted',action='read',iostat=ier)
    if (ier /= 0) then
      write(*,*) '  kernel not found: ',trim(k_file)
      stop 'Error kernel file not found'
    endif
    read(IIN) kernel
    close(IIN)

    ! outputs norm of kernel
    norm = sum( kernel * kernel )
    call sum_all_dp(norm, norm_sum)
    if (myrank == 0) then
      print*,'  norm kernel        : ',sqrt(norm_sum)
    endif

    ! approximate Hessian
    hess = 0._CUSTOM_REAL
    write(k_file,'(a,i6.6,a)') 'INPUT_KERNELS/'//trim(kernel_list(iker)) &
                          //'/proc',myrank,trim(REG)//'hess_kernel.bin'

    open(IIN,file=trim(k_file),status='old',form='unformatted',action='read',iostat=ier)
    if (ier /= 0) then
      write(*,*) '  hessian kernel not found: ',trim(k_file)
      stop 'Error hess_kernel.bin files not found'
    endif

    read(IIN) hess
    close(IIN)

    ! outputs norm of preconditioner
    norm = sum( hess * hess )
    call sum_all_dp(norm, norm_sum)
    if (myrank == 0) then
      print*,'  norm preconditioner: ',sqrt(norm_sum)
    endif

    ! note: we take absolute values for hessian (as proposed by Yang)
    hess = abs(hess)

    ! source mask
    if (USE_SOURCE_MASK) then
      ! reads in mask
      write(k_file,'(a,i6.6,a)') 'INPUT_KERNELS/'//trim(kernel_list(iker)) &
                            //'/proc',myrank,trim(REG)//'mask_source.bin'
      open(IIN,file=trim(k_file),status='old',form='unformatted',action='read',iostat=ier)
      if (ier /= 0) then
        write(*,*) '  file not found: ',trim(k_file)
        stop 'Error source mask file not found'
      endif
      read(IIN) mask_source
      close(IIN)

      ! masks source elements
      kernel = kernel * mask_source

    endif

    ! precondition
    if (USE_HESS_SUM) then

      ! sums up hessians first
      total_hess = total_hess + hess

    else

      ! inverts hessian
      call invert_hess( hess )

      ! preconditions each event kernel with its hessian
      kernel = kernel * hess

    endif

    ! sums all kernels from each event
    total_kernel = total_kernel + kernel

    if (myrank == 0) print*
  enddo

  ! preconditions summed kernels with summed hessians
  if (USE_HESS_SUM) then

      ! inverts hessian matrix
      call invert_hess( total_hess )

      ! preconditions kernel
      total_kernel = total_kernel * total_hess

  endif

  ! stores summed kernels
  if (myrank==0) write(*,*) 'writing out summed kernel for: ',trim(kernel_name)

  ! outputs summed kernel
  write(k_file,'(a,i6.6,a)') 'OUTPUT_SUM/proc',myrank,trim(REG) // trim(kernel_name) // '.bin'
  open(IOUT,file=trim(k_file),form='unformatted',status='unknown',action='write',iostat=ier)
  if (ier /= 0) then
    write(*,*) 'Error kernel not written: ',trim(k_file)
    stop 'Error kernel write'
  endif
  write(IOUT) total_kernel
  close(IOUT)

  ! outputs summed hessian
  if (USE_HESS_SUM) then
    if (myrank==0) write(*,*) 'writing out summed kernel for: ','hess_inv_kernel'
    write(k_file,'(a,i6.6,a)') 'OUTPUT_SUM/proc',myrank,trim(REG) // 'hess_inv_kernel' // '.bin'
    open(IOUT,file=trim(k_file),form='unformatted',status='unknown',action='write',iostat=ier)
    if (ier /= 0) then
      write(*,*) 'Error kernel not written: ',trim(k_file)
      stop 'Error kernel write'
    endif
    write(IOUT) total_hess
    close(IOUT)
  endif

  if (myrank==0) write(*,*)

  ! frees memory
  deallocate(kernel,hess,total_kernel)
  if (USE_HESS_SUM) deallocate(total_hess)
  if (USE_SOURCE_MASK) deallocate(mask_source)

end subroutine sum_kernel_pre

!
!-------------------------------------------------------------------------------------------------
!

subroutine invert_hess( hess_matrix )

! inverts the hessian matrix
! the approximate hessian is only defined for diagonal elements: like
! H_nn = \frac{ \partial^2 \chi }{ \partial \rho_n \partial \rho_n }
! on all GLL points, which are indexed (i,j,k,ispec)

  use tomography_par

  implicit none

  real(kind=CUSTOM_REAL), dimension(NGLLX,NGLLY,NGLLZ,NSPEC) :: hess_matrix

  ! local parameters
  real(kind=CUSTOM_REAL) :: maxh,maxh_all

  ! maximum value of hessian
  maxh = maxval( abs(hess_matrix) )

  ! determines maximum from all slices on master
  call max_all_all_cr(maxh, maxh_all)

  ! user output
  if (myrank == 0) then
    print*
    print*,'hessian maximum: ',maxh_all
    print*
  endif

  ! normalizes hessian
  if (maxh_all < 1.e-18) then
    ! hessian is zero, re-initializes
    hess_matrix = 1.0_CUSTOM_REAL
    !stop 'Error hessian too small'
  else
    ! since hessian has absolute values, this scales between [0,1]
    hess_matrix = hess_matrix / maxh_all
  endif


  ! inverts hessian values
  where( abs(hess_matrix(:,:,:,:)) > THRESHOLD_HESS )
    hess_matrix = 1.0_CUSTOM_REAL / hess_matrix
  elsewhere
    hess_matrix = 1.0_CUSTOM_REAL / THRESHOLD_HESS
  endwhere

  ! rescales hessian
  !hess_matrix = hess_matrix * maxh_all

end subroutine invert_hess
