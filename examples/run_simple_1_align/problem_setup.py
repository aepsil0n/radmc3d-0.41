#
# Import NumPy for array handling
#
import numpy as np
import math
#
# Import plotting libraries (start Python with ipython --matplotlib)
#
#from mpl_toolkits.mplot3d import axes3d
#from matplotlib import pyplot as plt
#
# Some natural constants
#
au  = 1.49598e13     # Astronomical Unit       [cm]
pc  = 3.08572e18     # Parsec                  [cm]
ms  = 1.98892e33     # Solar mass              [g]
ts  = 5.78e3         # Solar temperature       [K]
ls  = 3.8525e33      # Solar luminosity        [erg/s]
rs  = 6.96e10        # Solar radius            [cm]
#
# Monte Carlo parameters
#
nphot    = 1000000
#
# Grid parameters
#
nx       = 32
ny       = 32
nz       = 32
sizex    = 10*au
sizey    = 10*au
sizez    = 10*au
#
# Model parameters
#
radius   = 5*au
rho0     = 1e-16
#
# Star parameters
#
mstar    = ms
rstar    = rs
tstar    = ts
pstar    = np.array([0.,0.,0.])
#
# Make the coordinates
#
xi       = np.linspace(-sizex,sizex,nx+1)
yi       = np.linspace(-sizey,sizey,ny+1)
zi       = np.linspace(-sizez,sizez,nz+1)
xc       = 0.5 * ( xi[0:nx] + xi[1:nx+1] )
yc       = 0.5 * ( yi[0:ny] + yi[1:ny+1] )
zc       = 0.5 * ( zi[0:nz] + zi[1:nz+1] )
#
# Make the dust density model
#
qq       = np.meshgrid(xc,yc,zc,indexing='ij')
xx       = qq[0]
yy       = qq[1]
zz       = qq[2]
rr       = np.sqrt(xx**2+yy**2+zz**2)
rhod     = rho0 * np.exp(-(rr**2/radius**2)/2.0)
#
# Make the wavelength_micron.inp file
#
lam1     = 0.1e0
lam2     = 7.0e0
lam3     = 25.e0
lam4     = 1.0e4
n12      = 20
n23      = 100
n34      = 30
lam12    = np.logspace(np.log10(lam1),np.log10(lam2),n12,endpoint=False)
lam23    = np.logspace(np.log10(lam2),np.log10(lam3),n23,endpoint=False)
lam34    = np.logspace(np.log10(lam3),np.log10(lam4),n34,endpoint=True)
lam      = np.concatenate([lam12,lam23,lam34])
nlam     = lam.size
#
# parse the dustkapscatmat file to check how many wavelengths it has
# (necessary for creating the mock alignment factor file)
#
with open('dustkapscatmat_pyrmg70.inp','r') as f:
    for _ in range(7): f.readline()
    dustnf = int(f.readline())
    f.readline()
    dustfreq = np.zeros(dustnf)
    f.readline()
    for inu in range(dustnf):
        s=f.readline().split()
        dustfreq[inu] = float(s[0])
#
# Now make a mock alignment factor model. This is ONLY FOR TESTING.
# 
nrang = 20
muang = np.linspace(1.e0,0.e0,nrang)
eta   = np.arccos(muang)*180./math.pi
orth  = np.zeros(nrang) + 1.e0
ampl  = 0.5
para  = ( 1.e0 - ampl*np.cos(muang*math.pi) ) / ( 1.e0 + ampl)
#
# Now the alignment vector field.
#
alvec = np.zeros((nx,ny,nz,3))
#alvec[:,:,:,2] = 1.0   # Vertical field config
rrc       = np.sqrt(xx**2+yy**2)
alvec[:,:,:,0] = yy/rrc  # Circular field config (will automatically be normalized)
alvec[:,:,:,1] = -xx/rrc # Circular field config (will automatically be normalized)
#alvec[:,:,:,0] = xx/rrc  # Radial field config (will automatically be normalized)
#alvec[:,:,:,1] = yy/rrc  # Radial field config (will automatically be normalized)
#alvec[:,:,:,2] = 1e-6    # Make sure direc vector is never exactly 0
#alvec[:,:,:,0] = 1.0
#alvec[:,:,:,1] = 0.0
#alvec[:,:,:,2] = 0.0
#
# Write the wavelength file
#
with open('wavelength_micron.inp','w+') as f:
    f.write('%d\n'%(nlam))
    np.savetxt(f,lam.T,fmt=['%13.6e'])
#
#
# Write the stars.inp file
#
with open('stars.inp','w+') as f:
    f.write('2\n')
    f.write('1 %d\n\n'%(nlam))
    f.write('%13.6e %13.6e %13.6e %13.6e %13.6e\n\n'%(rstar,mstar,pstar[0],pstar[1],pstar[2]))
    np.savetxt(f,lam.T,fmt=['%13.6e'])
    f.write('\n%13.6e\n'%(-tstar))
#
# Write the grid file
#
with open('amr_grid.inp','w+') as f:
    f.write('1\n')                       # iformat
    f.write('0\n')                       # AMR grid style  (0=regular grid, no AMR)
    f.write('0\n')                       # Coordinate system
    f.write('0\n')                       # gridinfo
    f.write('1 1 1\n')                   # Include x,y,z coordinate
    f.write('%d %d %d\n'%(nx,ny,nz))     # Size of grid
    np.savetxt(f,xi.T,fmt=['%13.6e'])    # X coordinates (cell walls)
    np.savetxt(f,yi.T,fmt=['%13.6e'])    # Y coordinates (cell walls)
    np.savetxt(f,zi.T,fmt=['%13.6e'])    # Z coordinates (cell walls)
#
# Write the density file
#
with open('dust_density.inp','w+') as f:
    f.write('1\n')                       # Format number
    f.write('%d\n'%(nx*ny*nz))           # Nr of cells
    f.write('1\n')                       # Nr of dust species
    data = rhod.ravel(order='F')         # Create a 1-D view, fortran-style indexing
    np.savetxt(f,data.T,fmt=['%13.6e'])  # The data
#
# Dust opacity control file
#
with open('dustopac.inp','w+') as f:
    f.write('2               Format number of this file\n')
    f.write('1               Nr of dust species\n')
    f.write('============================================================================\n')
    f.write('20              Way in which this dust species is read\n')
    f.write('0               0=Thermal grain\n')
    f.write('pyrmg70         Extension of name of dustkappa_***.inp file\n')
    f.write('----------------------------------------------------------------------------\n')
#
# Dust alignment data
#
with open('dustkapalignfact_pyrmg70.inp','w+') as f:
    f.write('1\n')
    f.write('%d\n'%(dustnf))
    f.write('%d\n\n'%(nrang))
    np.savetxt(f,dustfreq.T,fmt=['%13.6e'])
    f.write('\n')
    np.savetxt(f,eta.T,fmt=['%13.6e'])
    f.write('\n')
    for inu in range(dustnf):
        for imu in range(nrang):
            f.write('%13.6e %13.6e\n'%(orth[imu],para[imu]))
        f.write('\n')
#
# Dust alignment direction
#
with open('grainalign_dir.inp','w+') as f:
    f.write('1\n')                       # Format number
    f.write('%d\n'%(nx*ny*nz))           # Nr of cells
    for iz in range(nz):
        for iy in range(ny):
            for ix in range(nx):
                f.write('%13.6e %13.6e %13.6e\n'%(alvec[ix,iy,iz,0],alvec[ix,iy,iz,1],alvec[ix,iy,iz,2]))
#
# Write the radmc3d.inp control file
#
with open('radmc3d.inp','w+') as f:
    f.write('nphot = %d\n'%(nphot))
    f.write('scattering_mode_max = 4\n')
    f.write('alignment_mode = -1\n')
    f.write('iranfreqmode = 1\n')

