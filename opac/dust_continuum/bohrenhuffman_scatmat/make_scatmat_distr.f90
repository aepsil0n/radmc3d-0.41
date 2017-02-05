!=======================================================================
!            MAKING OPACITY TABLE USING BOHREN-HUFFMAN PROGRAM 
!                        ADAPTED BY B.T. DRAINE
!           MADE INTO F90 AND INTO CURRENT FORM BY C.P. DULLEMOND
!
!***********************************************************************
! COMMENTS FROM ORIGINAL CODE:
! Program to interactively call Bohren-Huffman Mie theory program
!
! CALLBHMIE will interactively prompt for:
! 1. refractive index of surrounding medium
! 2. either refractive index or dielectric constant of sphere
! 3. radius of sphere
! 4. wavelength (in vacuo)
! 5. number of angles at which to calculate scattering intensities
!
! CALLBHMIE will return:
! 1. Q_ext, Q_abs, Q_sca, g, Q_back
! 2. If NANG>0, then will also return scattering matrix elements
!    S_11, S_33, S_34, and POL
!
! Adapted by B.T.Draine, Princeton Univ. Obs.
!***********************************************************************
!=======================================================================
program bhmakeopac
  implicit none
  integer, parameter :: MXNANG=1000
  integer :: IREADEP,J,NAN,NANG
  doubleprecision :: DANG,PI,sum,error,errmax
  real :: QABS,QBACK,QEXT,QSCA,RAD,REFMED,GSCA,POL
  real :: S11,S12,S33,S34,WAVEL,X
  complex :: REFREL,CXEPS,S1(2*MXNANG-1),S2(2*MXNANG-1)
  doubleprecision, allocatable :: lambda_cm(:),optcnst_n(:),optcnst_k(:)
  doubleprecision, allocatable :: kappa_abs(:),kappa_sca(:),kappa_g(:)
  doubleprecision, allocatable :: zscat(:,:,:),angle(:),mu(:),scalefact(:)
  doubleprecision, allocatable :: agrain_cm(:),dagr(:),weight(:),mgrain(:)
  integer :: nlam,ilam,nang180,nagr,ia,leng
  doubleprecision :: agrain_cm_min,agrain_cm_max,xigrain,dum(1:3)
  doubleprecision :: siggeom,factor,plindex
  character*160 :: filename,material,str0,str1
  logical :: notfinished
  PI=4.D0*ATAN(1.D0)
  !
  ! Defaults
  !
  REFMED = 1.d0
  errmax = 0.01
  !
  ! Open parameter file
  !
  open(unit=1,file='param_distr.inp')
  read(1,*) material
  read(1,*) nagr
  read(1,*) agrain_cm_min
  read(1,*) agrain_cm_max
  read(1,*) plindex           ! Should be -3.5 for standard MRN
  read(1,*) xigrain
  read(1,*) nang180           ! Nr of angles between 0 and 180 degrees
  read(1,*,end=209) errmax
209 continue
  close(1)
  filename = trim(material)//".lnk"
  !
  ! Do a check
  !
  if(nang180.lt.3) then
     write(*,*) 'This code is meant for making the full scattering matrix'
     write(*,*) 'at a set of discrete scattering angles. You must therefore'
     write(*,*) 'put nang0 (the fourth line of param.inp) to at least 3, but'
     write(*,*) 'preferably something like 90.'
     stop
  endif
  if(nang180.lt.60) then
     write(*,*) 'Warning: You have less than 60 angles between 0 and 180 deg.'
     write(*,*) 'Are you sure that this is what you want?'
  endif
  !
  ! Make the grain size grid
  !
  if(nagr.lt.4) then
     write(*,*) 'ERROR: Must have at least 4 grain size sampling points.'
     stop
  endif
  allocate(agrain_cm(nagr),dagr(nagr),weight(nagr),mgrain(nagr))
  do ia=1,nagr
     agrain_cm(ia) = agrain_cm_min * (agrain_cm_max/agrain_cm_min)**((ia-1.d0)/(nagr-1.d0))
  enddo
  dagr(1)    = 0.5d0*(agrain_cm(2)-agrain_cm(1))
  dagr(nagr) = 0.5d0*(agrain_cm(nagr)-agrain_cm(nagr-1))
  do ia=2,nagr-1 
     dagr(ia) = 0.5d0*(agrain_cm(ia+1)-agrain_cm(ia-1))
  enddo
  !
  ! Compute mass of grains
  !
  do ia=1,nagr
     mgrain(ia) = (4.d0*pi/3.d0)*xigrain*agrain_cm(ia)**3
  enddo
  !
  ! Make the grain size distribution according to the
  !
  !   N(a)da ~ a^plindex
  !
  ! recipe. Note: An MRN distribution has plindex = -3.5
  !
  sum = 0.d0
  do ia=1,nagr
     weight(ia) = agrain_cm(ia)**plindex * mgrain(ia) * dagr(ia)
     sum = sum + weight(ia)
  enddo
  weight(:) = weight(:) / sum
  !
  ! NANG=number of angles between 0 and 90 degrees (incl. 0 and 90)
  ! Scattering matrix elements are calculated for 2*NANG-1 angles
  ! including 0, 90, and 180 degrees.
  !
  IF(NANG180.GT.2*MXNANG-1)STOP'***Error: NANG > MXNANG'
  NANG=(NANG180+1)/2
  DANG=0.5d0*PI/(NANG-1.d0)
  NAN=NANG180
  allocate(mu(nan),angle(nan))
  do j=1,nan
     angle(j)=DANG*((1.d0*J)-1.E0)*180.E0/PI
     mu(j)=cos(angle(j)*PI/180.)
  enddo
  mu(1) = 1.0
  mu(nan) = -1.0
  !
  ! Open optical constants file
  !
  nlam = 0
  notfinished = .true.
  open(unit=1,file=filename)
  do while(notfinished)
     read(1,*,end=20) dum
     nlam = nlam + 1
  enddo
20 continue
  close(1)
  allocate(lambda_cm(nlam),optcnst_n(nlam),optcnst_k(nlam),scalefact(nlam))
  allocate(kappa_abs(nlam),kappa_sca(nlam),kappa_g(nlam))
  allocate(zscat(6,2*MXNANG-1,nlam))
  open(unit=1,file=filename)
  do ilam=1,nlam
     read(1,*) lambda_cm(ilam),optcnst_n(ilam),optcnst_k(ilam)
  enddo
  close(1)
  lambda_cm = lambda_cm * 1d-4
  !
  ! Reset things
  !
  zscat(:,:,:) = 0.d0
  kappa_abs(:) = 0.d0
  kappa_sca(:) = 0.d0
  kappa_g(:)   = 0.d0
  !
  ! Start the loop over grain sizes
  ! 
  do ia=1,nagr
     !
     ! Compute geometric cross section
     !
     siggeom = pi*agrain_cm(ia)**2
     !
     ! Now do the loop over wavelengths
     !
     do ilam=1,nlam
        !
        ! Prepare the parameters for BHMie
        !
        ! The complex index of refraction
        !
        refrel = cmplx(optcnst_n(ilam),optcnst_k(ilam))/refmed
        !
        ! Radius of the grain in cm
        !
        rad = agrain_cm(ia)
        !
        ! Wavelength in cm
        !
        wavel = lambda_cm(ilam)
        !
        ! Compute the dimensionless grain size size
        !
        X=2.E0*PI*RAD*REFMED/WAVEL
        !
        ! Call BHMie
        !
        CALL BHMIE(X,REFREL,NANG,S1,S2,QEXT,QSCA,QBACK,GSCA)
        QABS=QEXT-QSCA
        !
        ! Put results into array
        !
        ! Note: The averaging of g has to be done multiplied by kappa_scat, 
        !       otherwise the answer is wrong.
        !
        kappa_abs(ilam) = kappa_abs(ilam) + weight(ia)*qabs*siggeom/mgrain(ia)
        kappa_sca(ilam) = kappa_sca(ilam) + weight(ia)*qsca*siggeom/mgrain(ia)
        kappa_g(ilam)   = kappa_g(ilam)   + weight(ia)*GSCA*qsca*siggeom/mgrain(ia)
        !
        ! Compute conversion factor from the Sxx matrix elements
        ! from the Bohren & Huffman code to the Zxx matrix elements we
        ! use (such that 2*pi*int_{-1}^{+1}Z11(mu)dmu=kappa_scat).
        ! This includes the factor k^2 (wavenumber squared) to get 
        ! the actual cross section in units of cm^2 / ster, and there 
        ! is the mass of the grain to get the cross section per gram.
        !
        factor = (lambda_cm(ilam)/(2*PI))**2/mgrain(ia)
        !
        ! Also store the Z matrix elements
        !
        NAN=2*NANG-1
        DO J=1,NAN
           S11=0.5E0*CABS(S2(J))*CABS(S2(J))
           S11=S11+0.5E0*CABS(S1(J))*CABS(S1(J))
           S12=0.5E0*CABS(S2(J))*CABS(S2(J))
           S12=S12-0.5E0*CABS(S1(J))*CABS(S1(J))
           POL=-S12/S11
           S33=REAL(S2(J)*CONJG(S1(J)))
           S34=AIMAG(S2(J)*CONJG(S1(J)))
           zscat(1,j,ilam) = zscat(1,j,ilam) + weight(ia) * S11 * factor
           zscat(2,j,ilam) = zscat(2,j,ilam) + weight(ia) * S12 * factor
           zscat(3,j,ilam) = zscat(3,j,ilam) + weight(ia) * S11 * factor
           zscat(4,j,ilam) = zscat(4,j,ilam) + weight(ia) * S33 * factor
           zscat(5,j,ilam) = zscat(5,j,ilam) + weight(ia) * S34 * factor
           zscat(6,j,ilam) = zscat(6,j,ilam) + weight(ia) * S33 * factor
        enddo
        !
        ! End loop over all wavelengths
        !
     enddo
     !
     ! End loop over all grain sizes
     ! 
  enddo
  !
  ! Now renormalize the g factor
  ! 
  kappa_g(:) = kappa_g(:) / kappa_sca(:)
  !
  ! Check if the sum of the S11 over all angles is indeed kappa_scat
  !
  do ilam=1,nlam
     sum = 0.d0
     do j=2,nan
        sum = sum + 0.25d0*(zscat(1,j-1,ilam)+zscat(1,j,ilam))* &
              abs(mu(j)-mu(j-1))
     enddo
     sum = sum * 4*PI
     error = abs(sum/kappa_sca(ilam)-1.d0)
     if(error.gt.errmax) then
        write(*,*) 'ERROR: At lambda=',lambda_cm(ilam)*1d4,'micron the error in the',&
             ' scattering integral is ',error,'which is larger than the error limit',errmax
        write(*,*) '    kappa_scat                     = ',kappa_sca(ilam)
        write(*,*) '    2*pi*int_{-1}^{+1} Z_11(mu)dmu = ',sum
        write(*,*) '    Please use a larger number of angle points or take a weaker error limit (5th line in param.inp).'
        close(2)
        stop
     else
        scalefact(ilam) = kappa_sca(ilam) / sum
        zscat(1:6,1:nan,ilam) = zscat(1:6,1:nan,ilam) * scalefact(ilam)
     endif
  enddo
  !
  ! Write the results
  !
  filename = 'dustkapscatmat_'//trim(material)//'.inp'
  open(unit=2,file=filename)
  leng = len_trim(material)
  if(leng.lt.10) then
     write(str0,'(I1)')
  elseif(leng.lt.100) then
     write(str0,'(I2)')
  elseif(leng.lt.1000) then
     write(str0,'(I3)')
  else
     write(*,*) 'Dust opacity name too long'
     stop 
  endif
  str1 = '(A41,A'//trim(str0)//')'
  write(2,str1) '# Opacity and scattering matrix file for ',trim(material)
  write(2,'(A109)') '# Please do not forget to cite in your publications the original ' &
       //'paper of these optical constant measurements'
  write(2,'(A44)') '# Made with the make_scatmat_distr.f90 code,'
  write(2,'(A70)') '# using the bhmie.f Mie code of Bohren and Huffman (version by Draine)'
  write(2,'(A26)') '# Grain size distribution:'
  write(2,'(A23,E13.6,A3)') '#   agrain_min       = ',agrain_cm_min,' cm'
  write(2,'(A23,E13.6,A3)') '#   agrain_max       = ',agrain_cm_max,' cm'
  write(2,'(A23,F13.6)') '#   powerlaw index   = ',plindex
  write(2,'(A23,I4,A3)') '#   nr of sizes used = ',nagr
  write(2,'(A20,F9.6,A7)') '# Material density =',xigrain,' g/cm^3'
  write(2,*) 1     ! Format number
  write(2,*) nlam
  write(2,*) nan
  write(2,*) 
  do ilam=1,nlam
     write(2,'(4(E13.6,1X))') lambda_cm(ilam)*1e4,kappa_abs(ilam),kappa_sca(ilam),kappa_g(ilam)
  enddo
  write(2,*) 
  do j=1,nan
     write(2,'(F13.6)') angle(j)
  enddo
  write(2,*)
  do ilam=1,nlam
     do j=1,nan
        write(2,'(6(E13.6,1X))') zscat(1:6,j,ilam)
     enddo
     write(2,*)
  enddo
  close(2)
  !
  ! Just for information to the user: write out the scaling factor used
  !
  open(unit=1,file='scalefactor.out')
  write(1,*) nlam
  do ilam=1,nlam
     write(1,'(2(E13.6,1X))') lambda_cm(ilam)*1e4,scalefact(ilam)
  enddo
  close(1)
  !
  ! Deallocate stuff
  !
  deallocate(lambda_cm,optcnst_n,optcnst_k)
  deallocate(kappa_abs,kappa_sca,kappa_g)
  deallocate(zscat,angle,mu,scalefact)
  deallocate(agrain_cm,dagr,weight,mgrain)
end program bhmakeopac
