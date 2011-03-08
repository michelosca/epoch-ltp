MODULE sdf_output_util

  USE sdf_output
  USE sdf_output_cartesian
  USE sdf_output_point
  USE mpi

  IMPLICIT NONE

CONTAINS

  SUBROUTINE sdf_write_summary(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: i, errcode
    TYPE(sdf_block_type), POINTER :: b

    b => h%current_block

    h%summary_location = b%next_block_location
    h%current_location = h%summary_location
    CALL MPI_FILE_SEEK(h%filehandle, h%current_location, MPI_SEEK_SET, &
        errcode)

    b => h%blocklist
    b%block_start = h%current_location
    b%next_block_location = b%block_start + b%info_length
    b%done_header = .FALSE.
    h%current_block => b

    CALL sdf_write_block_info(h)

    DO i = 2,h%nblocks
      h%current_location = b%next_block_location
      b => b%next_block
      b%block_start = h%current_location
      b%next_block_location = b%block_start + b%info_length
      b%done_header = .FALSE.
      h%current_block => b

      CALL sdf_write_block_info(h)
    ENDDO

    h%summary_size = h%current_location - h%summary_location

  END SUBROUTINE sdf_write_summary



  SUBROUTINE sdf_write_block_info(h)

    TYPE(sdf_file_handle) :: h
    TYPE(sdf_block_type), POINTER :: b

    b => h%current_block

    IF (b%blocktype .EQ. c_blocktype_plain_mesh) THEN
      CALL write_mesh_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_point_mesh) THEN
      CALL write_point_mesh_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_plain_variable) THEN
      CALL write_mesh_variable_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_point_variable) THEN
      CALL write_point_variable_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_constant) THEN
      CALL write_constant_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_array) THEN
      CALL write_array_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_run_info) THEN
      CALL write_run_info_meta(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_source) THEN
      CALL write_block_header(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_stitched_tensor) THEN
      CALL sdf_write_stitched_tensor(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_stitched_material) THEN
      CALL sdf_write_stitched_material(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_stitched_matvar) THEN
      CALL sdf_write_stitched_matvar(h)
    ELSE IF (b%blocktype .EQ. c_blocktype_stitched_species) THEN
      CALL sdf_write_stitched_species(h)
    ELSE
      CALL write_block_header(h)
    ENDIF

  END SUBROUTINE sdf_write_block_info

END MODULE sdf_output_util