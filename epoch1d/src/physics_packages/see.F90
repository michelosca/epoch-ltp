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
!
! written by M. Osca Engelbrecht

MODULE see
#ifdef SEE
  USE strings_advanced
  USE shared_data
  USE random_generator
  USE partlist

  PRIVATE

  PUBLIC :: init_see_block, setup_see_model
  PUBLIC :: see_constant_yield
CONTAINS

  SUBROUTINE init_see_block(species_id)

    INTEGER, INTENT(IN) :: species_id
    TYPE(see_type), POINTER :: see_block

    IF (ASSOCIATED(species_list(species_id)%see)) THEN
      IF (rank == 0) THEN
        WRITE(*,*) '*** WARNING ***'
        WRITE(*,*) 'Species ',TRIM(ADJUSTL(species_list(species_id)%name)), &
          ' has already a SEE model associated. First defined models prevails.'
      END IF
      RETURN
    END IF

    ALLOCATE(species_list(species_id)%see)
    see_block => species_list(species_id)%see
    see_block%species_impact = species_id
    see_block%species_electron = -1
    see_block%const_yield_model = .FALSE.
    see_block%see_subroutine => NULL()
    see_block%see_temp = -1._num

  END SUBROUTINE init_see_block

  
  SUBROUTINE setup_see_model(see_block, model_str, errcode)

    TYPE(see_type), POINTER, INTENT(INOUT) :: see_block
    CHARACTER(*), INTENT(IN) :: model_str
    INTEGER, INTENT(INOUT) :: errcode

    IF (str_cmp(model_str, 'constant_yield')) THEN
      see_block%const_yield_model = .TRUE.
      ALLOCATE(see_block%cross_section(1))
      see_block%cross_section = -1._num
      see_block%see_subroutine => see_constant_yield 
    ELSE
      errcode = c_err_required_element_not_set 
    END IF

  END SUBROUTINE setup_see_model


  SUBROUTINE see_constant_yield(current_part, ispecies, x_dir, rm_flag)

    TYPE(particle), POINTER, INTENT(INOUT) :: current_part
    INTEGER, INTENT(IN) :: ispecies, x_dir
    LOGICAL, INTENT(INOUT) :: rm_flag
    TYPE(particle_species), POINTER :: impact_species
    TYPE(see_type), POINTER :: see_block
    TYPE(particle), POINTER :: electron_part
    REAL(num) :: ran, see_rate, mass, x_pos
    INTEGER :: ispecies_impact, ispecies_e
    REAL(num), DIMENSION(3) :: p_scat

    impact_species => species_list(ispecies)
    see_block => impact_species%see
    see_rate = see_block%cross_section(1)

    ran = random()
    IF (ran < see_rate) THEN
      ispecies_impact = see_block%species_impact
      ispecies_e = see_block%species_electron

      ! Slightly different process for ions and electrons
      IF (ispecies_e == ispecies) THEN
        mass = impact_species%mass
        electron_part => current_part
        rm_flag = .FALSE.
      ELSEIF (ispecies_impact == ispecies) THEN
        mass = species_list(ispecies_e)%mass
        CALL create_particle(electron_part)
        CALL add_particle_to_partlist(species_list(ispecies_e)%attached_list, &
          electron_part)
      END IF

      ! Scatter particle
      p_scat = random_momentum(mass, see_block%see_temp, x_dir)
      electron_part%part_p = p_scat

      ! Place particle
      ran = random()
      IF (x_dir==0) THEN
        x_pos = x_min + p_scat(1) / mass * ran * dt
      ELSEIF (x_dir==1) THEN
        x_pos = x_max + p_scat(1) / mass * ran * dt
      ENDIF
      electron_part%part_pos = x_pos

      NULLIFY(electron_part)
    END IF

    NULLIFY(see_block, impact_species)

  END SUBROUTINE see_constant_yield


  FUNCTION random_momentum(mass, temp, x_direction)

    INTEGER :: x_direction
    REAL(num), DIMENSION(3) :: random_momentum
    REAL(num) :: mass, var, temp

    var = SQRT(kb*temp*mass)

    IF (x_direction == 0) THEN ! Injection in x_min
      random_momentum(1) = var * SQRT(-2._num * LOG(random()))
    ELSE IF (x_direction == 1) THEN ! Injection in x_max
      random_momentum(1) = -var * SQRT(-2._num * LOG(random()))
    END IF
    random_momentum(2) = random_box_muller(var)
    random_momentum(3) = random_box_muller(var)

  END FUNCTION random_momentum

#endif
END MODULE see 
