! Copyright (C) 2009-2019 University of Warwick
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

MODULE calc_df

  USE boundary

  IMPLICIT NONE

CONTAINS

  SUBROUTINE calc_boundary(data_array, species)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN), OPTIONAL :: species

    CALL processor_summation_bcs(data_array, ng, species=species)

  END SUBROUTINE calc_boundary



  SUBROUTINE calc_mass_density(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_m
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num) :: fac, idx
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"

    data_array = 0.0_num
    part_m = 0.0_num
    fac = 0.0_num

    idx = 1.0_num / dx

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      part_m  = io_list(ispecies)%mass
      fac = io_list(ispecies)%weight
      wdata = part_m * fac

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
        part_m  = current%mass
#ifndef PER_SPECIES_WEIGHT
        fac = current%weight
#endif
        wdata = part_m * fac
#else
#ifndef PER_SPECIES_WEIGHT
        fac = current%weight
        wdata = part_m * fac
#endif
#endif

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
        END DO

        current => current%next
      END DO
      CALL calc_boundary(data_array, ispecies)
    END DO

    CALL calc_boundary(data_array)

    data_array = data_array * idx
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

  END SUBROUTINE calc_mass_density



  SUBROUTINE calc_ekbar(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_ux, part_uy, part_uz, part_mc, part_u2
    ! The weight of a particle
    REAL(num) :: part_w
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num) :: fac, gamma_rel, gamma_rel_m1
    REAL(num), DIMENSION(:), ALLOCATABLE :: wt
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"

    ALLOCATE(wt(1-ng:nx+ng))
    data_array = 0.0_num
    wt = 0.0_num
    part_mc  = 1.0_num
    part_w = 1.0_num

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (spec_sum .AND. &
          io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      part_mc = c * io_list(ispecies)%mass
      part_w = io_list(ispecies)%weight
      fac = part_mc * part_w * c

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
        part_mc = c * current%mass
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
#endif
        fac = part_mc * part_w * c
#else
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
        fac = part_mc * part_w * c
#endif
#endif

        IF (io_list(ispecies)%species_type /= c_species_id_photon) THEN
          part_ux = current%part_p(1) / part_mc
          part_uy = current%part_p(2) / part_mc
          part_uz = current%part_p(3) / part_mc

          part_u2 = part_ux**2 + part_uy**2 + part_uz**2
          gamma_rel = SQRT(part_u2 + 1.0_num)
          gamma_rel_m1 = part_u2 / (gamma_rel + 1.0_num)

          wdata = gamma_rel_m1 * fac
        ELSE
#if defined(PHOTONS) || defined(BREMSSTRAHLUNG)
          wdata = current%particle_energy * part_w
#else
          wdata = 0.0_num
#endif
        END IF

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
          wt(cell_x+ix) = wt(cell_x+ix) + gx(ix) * part_w
        END DO

        current => current%next
      END DO
      CALL calc_boundary(data_array, ispecies)
      CALL calc_boundary(wt, ispecies)
    END DO

    CALL calc_boundary(data_array)
    CALL calc_boundary(wt)

    data_array = data_array / MAX(wt, c_tiny)
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

    DEALLOCATE(wt)

  END SUBROUTINE calc_ekbar



  SUBROUTINE calc_ekflux(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_ux, part_uy, part_uz, part_mc, part_u2
    ! The weight of a particle
    REAL(num) :: part_w
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num) :: fac, gamma_rel, gamma_rel_m1, part_flux, xfac, yfac, zfac
    REAL(num), DIMENSION(:), ALLOCATABLE :: wt
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"

    ALLOCATE(wt(1-ng:nx+ng))
    data_array = 0.0_num
    wt = 0.0_num
    part_mc  = 1.0_num
    part_w = 1.0_num

    xfac = c
    yfac = c * dx
    zfac = c * dx

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (spec_sum .AND. &
          io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      part_mc = c * io_list(ispecies)%mass
      part_w = io_list(ispecies)%weight
      fac = part_mc * part_w * c

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
        part_mc = c * current%mass
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
#endif
        fac = part_mc * part_w * c
#else
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
        fac = part_mc * part_w * c
#endif
#endif

        IF (io_list(ispecies)%species_type /= c_species_id_photon) THEN
          part_ux = current%part_p(1) / part_mc
          part_uy = current%part_p(2) / part_mc
          part_uz = current%part_p(3) / part_mc

          part_u2 = part_ux**2 + part_uy**2 + part_uz**2
          gamma_rel = SQRT(part_u2 + 1.0_num)
          gamma_rel_m1 = part_u2 / (gamma_rel + 1.0_num)

          wdata = gamma_rel_m1 * fac
        ELSE
#if defined(PHOTONS) || defined(BREMSSTRAHLUNG)
          fac = c / current%particle_energy
          part_ux = current%part_p(1) * fac
          part_uy = current%part_p(2) * fac
          part_uz = current%part_p(3) * fac
          gamma_rel = 1.0_num
          wdata = current%particle_energy * part_w
#else
          gamma_rel = 1.0_num
          wdata = 0.0_num
#endif
        END IF

        SELECT CASE(direction)
        CASE(-c_dir_x)
          ! negative flux in x
          part_flux = xfac * part_ux / gamma_rel
          wdata = -wdata * MIN(part_flux, 0.0_num)
        CASE( c_dir_x)
          ! positive flux in x
          part_flux = xfac * part_ux / gamma_rel
          wdata =  wdata * MAX(part_flux, 0.0_num)
        CASE(-c_dir_y)
          ! negative flux in y
          part_flux = yfac * part_uy / gamma_rel
          wdata = -wdata * MIN(part_flux, 0.0_num)
        CASE( c_dir_y)
          ! positive flux in y
          part_flux = yfac * part_uy / gamma_rel
          wdata =  wdata * MAX(part_flux, 0.0_num)
        CASE(-c_dir_z)
          ! negative flux in z
          part_flux = zfac * part_uz / gamma_rel
          wdata = -wdata * MIN(part_flux, 0.0_num)
        CASE( c_dir_z)
          ! positive flux in z
          part_flux = zfac * part_uz / gamma_rel
          wdata =  wdata * MAX(part_flux, 0.0_num)
        END SELECT

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
          wt(cell_x+ix) = wt(cell_x+ix) + gx(ix) * part_w
        END DO

        current => current%next
      END DO
      CALL calc_boundary(data_array, ispecies)
      CALL calc_boundary(wt, ispecies)
    END DO

    CALL calc_boundary(data_array)
    CALL calc_boundary(wt)

    data_array = data_array / MAX(wt, c_tiny)
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

    DEALLOCATE(wt)

  END SUBROUTINE calc_ekflux



  SUBROUTINE calc_poynt_flux(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    INTEGER :: ix
    REAL(num) :: ex_cc, ey_cc, ez_cc, bx_cc, by_cc, bz_cc

    SELECT CASE(direction)
    CASE(c_dir_x)
      DO ix = 1, nx
        ey_cc = ey(ix)
        ez_cc = ez(ix)
        by_cc = 0.5_num * (by(ix-1) + by(ix))
        bz_cc = 0.5_num * (bz(ix-1) + bz(ix))
        data_array(ix) = (ey_cc * bz_cc - ez_cc * by_cc) / mu0
      END DO
    CASE(c_dir_y)
      DO ix = 1, nx
        ex_cc = 0.5_num * (ex(ix-1) + ex(ix))
        ez_cc = ez(ix)
        bx_cc = bx(ix)
        bz_cc = 0.5_num * (bz(ix-1) + bz(ix))
        data_array(ix) = (ez_cc * bx_cc - ex_cc * bz_cc) / mu0
      END DO
    CASE(c_dir_z)
      DO ix = 1, nx
        ex_cc = 0.5_num * (ex(ix-1) + ex(ix))
        ey_cc = ey(ix)
        bx_cc = bx(ix)
        by_cc = 0.5_num * (by(ix-1) + by(ix))
        data_array(ix) = (ex_cc * by_cc - ey_cc * bx_cc) / mu0
      END DO
    END SELECT

  END SUBROUTINE calc_poynt_flux



  SUBROUTINE calc_charge_density(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_q
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num) :: fac, idx
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"

    data_array = 0.0_num
    part_q = 0.0_num
    fac = 0.0_num

    idx = 1.0_num / dx

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      part_q  = io_list(ispecies)%charge
      fac = io_list(ispecies)%weight
      wdata = part_q * fac

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
        part_q  = current%charge
#ifndef PER_SPECIES_WEIGHT
        fac = current%weight
#endif
        wdata = part_q * fac
#else
#ifndef PER_SPECIES_WEIGHT
        fac = current%weight
        wdata = part_q * fac
#endif
#endif

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
        END DO

        current => current%next
      END DO
      CALL calc_boundary(data_array, ispecies)
    END DO

    CALL calc_boundary(data_array)

    data_array = data_array * idx
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

  END SUBROUTINE calc_charge_density



  SUBROUTINE calc_number_density(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num) :: idx, vol
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"
    data_array = 0.0_num

    vol = dx
    idx = 1.0_num / vol

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (spec_sum &
          .AND. io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      IF (io_list(ispecies)%background_species) THEN
        data_array(1:nx) = data_array(1:nx) &
            + io_list(ispecies)%background_density(1:nx) * vol
      ELSE
        current => io_list(ispecies)%attached_list%head
        wdata = io_list(ispecies)%weight

        DO WHILE (ASSOCIATED(current))
#ifndef PER_SPECIES_WEIGHT
          wdata = current%weight
#endif

#include "particle_to_grid.inc"

          DO ix = sf_min, sf_max
            data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
          END DO

          current => current%next
        END DO
      END IF
      CALL calc_boundary(data_array, ispecies)
    END DO

    CALL calc_boundary(data_array)

    data_array = data_array * idx
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

  END SUBROUTINE calc_number_density



  SUBROUTINE calc_ppc(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    INTEGER :: ispecies, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
    REAL(num) :: cell_x_r
    INTEGER :: cell_x

    data_array = 0.0_num

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head

      DO WHILE (ASSOCIATED(current))
#ifdef PARTICLE_SHAPE_TOPHAT
        cell_x_r = (current%part_pos - x_grid_min_local) / dx
#else
        cell_x_r = (current%part_pos - x_grid_min_local) / dx + 0.5_num
#endif
        cell_x = FLOOR(cell_x_r) + 1

        data_array(cell_x) = data_array(cell_x) + 1.0_num

        current => current%next
      END DO
    END DO

  END SUBROUTINE calc_ppc



  SUBROUTINE calc_average_weight(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num), DIMENSION(:), ALLOCATABLE :: part_count
    INTEGER :: ispecies, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
    REAL(num) :: cell_x_r
    INTEGER :: cell_x

    data_array = 0.0_num

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    ALLOCATE(part_count(1-ng:nx+ng))
    part_count = 0.0_num

    DO ispecies = spec_start, spec_end
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      wdata = io_list(ispecies)%weight

      DO WHILE (ASSOCIATED(current))
#ifndef PER_SPECIES_WEIGHT
        wdata = current%weight
#endif

#ifdef PARTICLE_SHAPE_TOPHAT
        cell_x_r = (current%part_pos - x_grid_min_local) / dx
#else
        cell_x_r = (current%part_pos - x_grid_min_local) / dx + 0.5_num
#endif
        cell_x = FLOOR(cell_x_r) + 1

        data_array(cell_x) = data_array(cell_x) + wdata
        part_count(cell_x) = part_count(cell_x) + 1.0_num

        current => current%next
      END DO
    END DO

    data_array = data_array / MAX(part_count, c_tiny)

    DEALLOCATE(part_count)

  END SUBROUTINE calc_average_weight



  SUBROUTINE calc_temperature(sigma, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: sigma
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_pmx, part_pmy, part_pmz, sqrt_part_m
    ! The weight of a particle
    REAL(num) :: part_w
    REAL(num) :: gf
    REAL(num), DIMENSION(:), ALLOCATABLE :: part_count, meanx, meany, meanz
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
    REAL(num) :: dof, wdata
    INTEGER :: dir

#include "particle_head.inc"

    ALLOCATE(meanx(1-ng:nx+ng))
    ALLOCATE(meany(1-ng:nx+ng))
    ALLOCATE(meanz(1-ng:nx+ng))
    ALLOCATE(part_count(1-ng:nx+ng))
    meanx = 0.0_num
    meany = 0.0_num
    meanz = 0.0_num
    part_count = 0.0_num
    sigma = 0.0_num

    IF (PRESENT(direction)) THEN
      dir = direction
      dof = 1.0_num
    ELSE
      dir = -1
      dof = 3.0_num
    END IF

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      sqrt_part_m  = SQRT(io_list(ispecies)%mass)
      part_w = io_list(ispecies)%weight

      DO WHILE(ASSOCIATED(current))
#ifdef PER_PARTICLE_CHARGE_MASS
        sqrt_part_m  = SQRT(current%mass)
#endif
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
#endif
        ! Copy the particle properties out for speed
        part_pmx = current%part_p(1) / sqrt_part_m
        part_pmy = current%part_p(2) / sqrt_part_m
        part_pmz = current%part_p(3) / sqrt_part_m

#include "particle_to_grid.inc"

        SELECT CASE(dir)
          CASE(c_dir_x)
            DO ix = sf_min, sf_max
              gf = gx(ix) * part_w
              meanx(cell_x+ix) = meanx(cell_x+ix) + gf * part_pmx
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
          CASE(c_dir_y)
            DO ix = sf_min, sf_max
              gf = gx(ix) * part_w
              meany(cell_x+ix) = meany(cell_x+ix) + gf * part_pmy
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
          CASE(c_dir_z)
            DO ix = sf_min, sf_max
              gf = gx(ix) * part_w
              meanz(cell_x+ix) = meanz(cell_x+ix) + gf * part_pmz
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
          CASE DEFAULT
            DO ix = sf_min, sf_max
              gf = gx(ix) * part_w
              meanx(cell_x+ix) = meanx(cell_x+ix) + gf * part_pmx
              meany(cell_x+ix) = meany(cell_x+ix) + gf * part_pmy
              meanz(cell_x+ix) = meanz(cell_x+ix) + gf * part_pmz
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
        END SELECT
        current => current%next
      END DO

      SELECT CASE(dir)
        CASE(c_dir_x)
          CALL calc_boundary(meanx, ispecies)
        CASE(c_dir_y)
          CALL calc_boundary(meany, ispecies)
        CASE(c_dir_z)
          CALL calc_boundary(meanz, ispecies)
        CASE DEFAULT
          CALL calc_boundary(meanx, ispecies)
          CALL calc_boundary(meany, ispecies)
          CALL calc_boundary(meanz, ispecies)
      END SELECT

      CALL calc_boundary(part_count, ispecies)
    END DO

    SELECT CASE(dir)
      CASE(c_dir_x)
        CALL calc_boundary(meanx)
      CASE(c_dir_y)
        CALL calc_boundary(meany)
      CASE(c_dir_z)
        CALL calc_boundary(meanz)
      CASE DEFAULT
        CALL calc_boundary(meanx)
        CALL calc_boundary(meany)
        CALL calc_boundary(meanz)
    END SELECT
    CALL calc_boundary(part_count)

    part_count = MAX(part_count, 1.e-6_num)

    meanx = meanx / part_count
    meany = meany / part_count
    meanz = meanz / part_count

    ! Restore ghost cell values for means
    SELECT CASE(dir)
      CASE(c_dir_x)
        CALL field_bc(meanx, ng)
      CASE(c_dir_y)
        CALL field_bc(meany, ng)
      CASE(c_dir_z)
        CALL field_bc(meanz, ng)
      CASE DEFAULT
        CALL field_bc(meanx, ng)
        CALL field_bc(meany, ng)
        CALL field_bc(meanz, ng)
    END SELECT

    part_count = 0.0_num
    DO ispecies = spec_start, spec_end
      IF (io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      sqrt_part_m  = SQRT(io_list(ispecies)%mass)

      DO WHILE(ASSOCIATED(current))
#ifdef PER_PARTICLE_CHARGE_MASS
        sqrt_part_m  = SQRT(current%mass)
#endif
        ! Copy the particle properties out for speed
        part_pmx = current%part_p(1) / sqrt_part_m
        part_pmy = current%part_p(2) / sqrt_part_m
        part_pmz = current%part_p(3) / sqrt_part_m

#include "particle_to_grid.inc"

        SELECT CASE(dir)
          CASE(c_dir_x)
            DO ix = sf_min, sf_max
              gf = gx(ix)
              wdata = (part_pmx - meanx(cell_x+ix))**2
              sigma(cell_x+ix) = sigma(cell_x+ix) + gf * wdata
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
          CASE(c_dir_y)
            DO ix = sf_min, sf_max
              gf = gx(ix)
              wdata = (part_pmy - meany(cell_x+ix))**2
              sigma(cell_x+ix) = sigma(cell_x+ix) + gf * wdata
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
          CASE(c_dir_z)
            DO ix = sf_min, sf_max
              gf = gx(ix)
              wdata = (part_pmz - meanz(cell_x+ix))**2
              sigma(cell_x+ix) = sigma(cell_x+ix) + gf * wdata
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
          CASE DEFAULT
            DO ix = sf_min, sf_max
              gf = gx(ix)
              wdata = (part_pmx - meanx(cell_x+ix))**2 &
                    + (part_pmy - meany(cell_x+ix))**2 &
                    + (part_pmz - meanz(cell_x+ix))**2
              sigma(cell_x+ix) = sigma(cell_x+ix) + gf * wdata
              part_count(cell_x+ix) = part_count(cell_x+ix) + gf
            END DO
        END SELECT
        current => current%next
      END DO
      CALL calc_boundary(sigma, ispecies)
      CALL calc_boundary(part_count, ispecies)
    END DO

    CALL calc_boundary(sigma)
    CALL calc_boundary(part_count)

    ! 3/2 kT = <p^2>/(2m)
    sigma = sigma / MAX(part_count, 1.e-6_num) / kb / dof

    DEALLOCATE(part_count, meanx, meany, meanz)

  END SUBROUTINE calc_temperature



  SUBROUTINE calc_per_species_current(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_q, part_mc
#ifndef ELECTROSTATIC
    REAL(num) :: part_px, part_py, part_pz
    REAL(num) :: root
#else
    REAL(num) :: part_p
#endif
    ! The data to be weighted onto the grid
    REAL(num) :: wdata, part_w
    REAL(num) :: fac, idx
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"

    IF (.NOT. PRESENT(direction)) THEN
      IF (rank == 0) THEN
        PRINT*, 'Error: No direction argument supplied to ', &
            'calc_per_species_current'
        CALL abort_code(c_err_bad_value)
      END IF
    END IF

    data_array = 0.0_num
    part_q = 0.0_num
    fac = 0.0_num

    idx = 1.0_num / dx

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head
      part_q  = io_list(ispecies)%charge
      part_w = io_list(ispecies)%weight
#ifdef ELECTROSTATIC
      part_mc = io_list(ispecies)%mass
      fac = part_w * part_q / part_mc
#else
      part_mc = c * io_list(ispecies)%mass
      fac = part_w * part_q
#endif

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
!>
!>>
#ifdef ELECTROSTATIC
        part_mc = current%mass
#else
        part_mc = c * current%mass
#endif
!<<
        part_q  = current%charge

!>>
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
#endif
!<<

!>>
#ifdef ELECTROSTATIC
        fac = part_w * part_q / part_mc
#else
        fac = part_w * part_q
#endif
!<<

!> in case not PER_PARTICLE_CHARGE_MASS
#else

!>>
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
!>>>
#ifdef ELECTROSTATIC
        fac = part_w * part_q / part_mc
#else
        fac = part_w * part_q
#endif
!<<<
#endif
!<<
#endif
!<

        ! Copy the particle properties out for speed
#ifndef ELECTROSTATIC
        part_px = current%part_p(1)
        part_py = current%part_p(2)
        part_pz = current%part_p(3)
        root = 1.0_num / SQRT(part_mc**2 + part_px**2 + part_py**2 + part_pz**2)
        SELECT CASE (direction)
          CASE(c_dir_x)
            wdata = fac * part_px * root
          CASE(c_dir_y)
            wdata = fac * part_py * root
          CASE(c_dir_z)
            wdata = fac * part_pz * root
        END SELECT
#else
! Electrostatic case
        SELECT CASE (direction)
          CASE(c_dir_x)
            part_p = current%part_p(1)
            wdata = fac * part_p
          CASE(c_dir_y)
            part_p = current%part_p(2)
            wdata = fac * part_p
          CASE(c_dir_z)
            part_p = current%part_p(3)
            wdata = fac * part_p
        END SELECT
#endif

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
        END DO

        current => current%next
      END DO
      CALL calc_boundary(data_array, ispecies)
    END DO

    CALL calc_boundary(data_array)

#ifndef ELECTROSTATIC
    idx = c * idx
#else
    idx = idx
#endif
    data_array = data_array * idx
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

  END SUBROUTINE calc_per_species_current



  SUBROUTINE calc_average_momentum(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction
    REAL(num), DIMENSION(:), ALLOCATABLE :: part_count
    ! The data to be weighted onto the grid
    REAL(num) :: wdata, weight
    INTEGER :: ispecies, ix, spec_start, spec_end
    TYPE(particle), POINTER :: current
    LOGICAL :: spec_sum
#include "particle_head.inc"

    IF (.NOT. PRESENT(direction)) THEN
      IF (rank == 0) THEN
        PRINT*, 'Error: No direction argument supplied to calc_average_momentum'
        CALL abort_code(c_err_bad_value)
      END IF
    END IF

    ALLOCATE(part_count(1-ng:nx+ng))

    part_count = 0.0_num
    data_array = 0.0_num

    spec_start = current_species
    spec_end = current_species
    spec_sum = .FALSE.

    IF (current_species <= 0) THEN
      spec_start = 1
      spec_end = n_species
      spec_sum = .TRUE.
    END IF

    DO ispecies = spec_start, spec_end
      IF (io_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (spec_sum .AND. io_list(ispecies)%zero_current) CYCLE
#endif
      current => io_list(ispecies)%attached_list%head

      weight = io_list(ispecies)%weight

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifndef PER_SPECIES_WEIGHT
        weight = current%weight
#endif
        wdata = weight * current%part_p(direction)

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          data_array(cell_x+ix) = data_array(cell_x+ix) + gx(ix) * wdata
          part_count(cell_x+ix) = part_count(cell_x+ix) + gx(ix) * weight
        END DO

        current => current%next
      END DO
      CALL calc_boundary(data_array, ispecies)
      CALL calc_boundary(part_count, ispecies)
    END DO

    CALL calc_boundary(data_array)
    CALL calc_boundary(part_count)

    data_array = data_array / MAX(part_count, c_tiny)
    DO ix = 1, 2*c_ndims
      CALL field_zero_gradient(data_array, c_stagger_centre, ix)
    END DO

    DEALLOCATE(part_count)

  END SUBROUTINE calc_average_momentum



  SUBROUTINE calc_total_energy_sum(per_species)

    LOGICAL, INTENT(IN) :: per_species
    REAL(num) :: particle_energy, field_energy
    REAL(num) :: part_ux, part_uy, part_uz, part_u2
    REAL(num) :: part_mc, part_w, fac, gamma_rel, gamma_rel_m1, part_energy
    REAL(num), ALLOCATABLE :: sum_out(:), sum_in(:)
    REAL(num), ALLOCATABLE :: species_energy(:)
    REAL(num), PARAMETER :: c2 = c**2
    INTEGER :: ispecies, i, nsum
    TYPE(particle), POINTER :: current

    particle_energy = 0.0_num
    IF (per_species) THEN
      ALLOCATE(species_energy(n_species))
      nsum = 1 + n_species
    ELSE
      nsum = 2
    END IF

    ! Sum over all particles to calculate total kinetic energy
    DO ispecies = 1, n_species
#ifndef NO_TRACER_PARTICLES
      IF (species_list(ispecies)%zero_current) CYCLE
#endif
      current => species_list(ispecies)%attached_list%head
      part_mc = c * species_list(ispecies)%mass
      part_w = species_list(ispecies)%weight
      fac = part_mc * part_w * c
      part_energy = 0.0_num

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
        part_mc = c * current%mass
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
#endif
        fac = part_mc * part_w * c
#else
#ifndef PER_SPECIES_WEIGHT
        part_w = current%weight
        fac = part_mc * part_w * c
#endif
#endif

        IF (species_list(ispecies)%species_type /= c_species_id_photon) THEN
          part_ux = current%part_p(1) / part_mc
          part_uy = current%part_p(2) / part_mc
          part_uz = current%part_p(3) / part_mc

          part_u2 = part_ux**2 + part_uy**2 + part_uz**2
          gamma_rel = SQRT(part_u2 + 1.0_num)
          gamma_rel_m1 = part_u2 / (gamma_rel + 1.0_num)

          part_energy = part_energy + gamma_rel_m1 * fac
#if defined(PHOTONS) || defined(BREMSSTRAHLUNG)
        ELSE
          part_energy = part_energy + current%particle_energy * part_w
#endif
        END IF

        current => current%next
      END DO
      IF (per_species) species_energy(ispecies) = part_energy
      particle_energy = particle_energy + part_energy
    END DO

    ! EM field energy
    field_energy = 0.0_num
    DO i = 1, nx
      field_energy = field_energy + ex(i)**2 + ey(i)**2 &
          + ez(i)**2 + c2 * (bx(i)**2 + by(i)**2 + bz(i)**2)
    END DO
    field_energy = 0.5_num * epsilon0 * field_energy * dx

    ALLOCATE(sum_out(nsum))
    ALLOCATE(sum_in(nsum))
    sum_out(1) = field_energy
    IF (per_species) THEN
      sum_out(2:1+n_species) = species_energy(:)
    ELSE
      sum_out(2) = particle_energy
    END IF

    CALL MPI_REDUCE(sum_out, sum_in, nsum, mpireal, MPI_SUM, 0, comm, errcode)
    total_field_energy = sum_in(1)
    IF (per_species) THEN
      total_particle_energy_species(:) = sum_in(2:1+n_species)
      total_particle_energy = SUM(sum_in(2:1+n_species))
    ELSE
      total_particle_energy = sum_in(2)
    END IF

  END SUBROUTINE calc_total_energy_sum



  SUBROUTINE calc_initial_current

    REAL(num), DIMENSION(:), ALLOCATABLE :: jx, jy, jz
    ! Properties of the current particle. Copy out of particle arrays for speed
    REAL(num) :: part_q, part_mc
    REAL(num) :: part_px, part_py, part_pz
    ! The data to be weighted onto the grid
    REAL(num) :: wdata
    REAL(num) :: part_jx, part_jy, part_jz
    REAL(num) :: fac, idx, root
    REAL(num) :: sum_in(3), sum_out(3)
    INTEGER :: ispecies, ix
    TYPE(particle), POINTER :: current
#include "particle_head.inc"

    ALLOCATE(jx(1-jng:nx+jng))
    ALLOCATE(jy(1-jng:nx+jng))
    ALLOCATE(jz(1-jng:nx+jng))

    jx = 0.0_num
    jy = 0.0_num
    jz = 0.0_num

    idx = 1.0_num / dx

    DO ispecies = 1, n_species
      IF (species_list(ispecies)%species_type == c_species_id_photon) CYCLE
#ifndef NO_TRACER_PARTICLES
      IF (species_list(ispecies)%zero_current) CYCLE
#endif
      current => species_list(ispecies)%attached_list%head
      part_mc = c * species_list(ispecies)%mass
      part_q  = species_list(ispecies)%charge
      fac = species_list(ispecies)%weight
      wdata = part_q * fac

      DO WHILE (ASSOCIATED(current))
        ! Copy the particle properties out for speed
#ifdef PER_PARTICLE_CHARGE_MASS
        part_mc = c * current%mass
        part_q  = current%charge
#ifndef PER_SPECIES_WEIGHT
        fac = current%weight
#endif
        wdata = part_q * fac
#else
#ifndef PER_SPECIES_WEIGHT
        fac = current%weight
        wdata = part_q * fac
#endif
#endif

        ! Copy the particle properties out for speed
        part_px = current%part_p(1)
        part_py = current%part_p(2)
        part_pz = current%part_p(3)
        root = 1.0_num / SQRT(part_mc**2 + part_px**2 + part_py**2 + part_pz**2)

        part_jx = wdata * part_px * root
        part_jy = wdata * part_py * root
        part_jz = wdata * part_pz * root

#include "particle_to_grid.inc"

        DO ix = sf_min, sf_max
          jx(cell_x+ix) = jx(cell_x+ix) + gx(ix) * part_jx
          jy(cell_x+ix) = jy(cell_x+ix) + gx(ix) * part_jy
          jz(cell_x+ix) = jz(cell_x+ix) + gx(ix) * part_jz
        END DO

        current => current%next
      END DO
    END DO

    sum_out(1) = SUM(jx)
    sum_out(2) = SUM(jy)
    sum_out(3) = SUM(jz)
    DEALLOCATE(jx, jy, jz)

    CALL MPI_ALLREDUCE(sum_out, sum_in, 3, mpireal, MPI_SUM, comm, errcode)

    fac = c * idx / nx_global

    initial_jx = sum_in(1) * fac
    initial_jy = sum_in(2) * fac
    initial_jz = sum_in(3) * fac

  END SUBROUTINE calc_initial_current



#ifdef NEUTRAL_COLLISIONS
  SUBROUTINE calc_neutral_collisions(data_array, current_species, direction)

    REAL(num), DIMENSION(1-ng:), INTENT(OUT) :: data_array
    INTEGER, INTENT(IN) :: current_species
    INTEGER, INTENT(IN), OPTIONAL :: direction

    INTEGER :: ispecies, jspecies, nc_type, coll_index
    TYPE(neutrals_block), POINTER :: collision_block
    TYPE(collision_type_block), POINTER :: coll_type_block

    data_array = 0._num

    IF (current_species == 0) THEN ! Adds all collisions together
      DO ispecies = 1, n_species
        DO jspecies = ispecies, n_species_bg
          IF (.NOT.neutral_coll(ispecies, jspecies)) CYCLE
          collision_block => species_list(ispecies)%neutrals(jspecies)
          DO nc_type = 1, collision_block%ncolltypes
            coll_type_block => collision_block%collision_set(nc_type)
            data_array(1:nx) = data_array(1:nx) &
#ifdef PER_SPECIES_WEIGHT
              + REAL(coll_type_block%coll_counter,num) * &
              collision_block%min_weight
#else
              + REAL(coll_type_block%coll_counter,num)
#endif
          END DO
        END DO
      END DO
    ! Looks for a specific collision type
    ! For AVERAGE puposes
    ELSEIF (current_species > 0 .AND. .NOT.PRESENT(direction)) THEN
      coll_index = 0
      DO ispecies = 1, n_species
        DO jspecies = ispecies, n_species_bg
          IF (.NOT.neutral_coll(ispecies, jspecies)) CYCLE
          collision_block => species_list(ispecies)%neutrals(jspecies)
          DO nc_type = 1, collision_block%ncolltypes
            coll_index = coll_index + 1
            IF (coll_index == current_species) THEN
              coll_type_block => collision_block%collision_set(nc_type)
              data_array(1:nx) = REAL(coll_type_block%coll_counter,num)
#ifdef PER_SPECIES_WEIGHT
              data_array(1:nx) = data_array(1:nx) * &
                collision_block%min_weight
#endif
              RETURN
            END IF
          END DO
        END DO
      END DO

    ! For diagnostics.F90>write_nspecies_field
    ELSEIF (current_species > 0 .AND. PRESENT(direction)) THEN
      coll_index = 0
      DO jspecies = current_species, n_species_bg
        IF (.NOT.neutral_coll(current_species, jspecies)) CYCLE
        collision_block => species_list(current_species)%neutrals(jspecies)
        DO nc_type = 1, collision_block%ncolltypes
          coll_index = coll_index + 1
          IF (coll_index == direction) THEN
            coll_type_block => collision_block%collision_set(nc_type)
            data_array(1:nx) = REAL(coll_type_block%coll_counter,num)
#ifdef PER_SPECIES_WEIGHT
            data_array(1:nx) = data_array(1:nx) * &
              collision_block%min_weight
#endif
            RETURN
          END IF
        END DO
      END DO
    END IF

  END SUBROUTINE calc_neutral_collisions
#endif

END MODULE calc_df
