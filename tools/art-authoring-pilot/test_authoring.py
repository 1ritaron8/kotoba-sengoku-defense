"""Tests for portable preparation/guards; not Blender/Godot/visual tests."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock
import authoring as a


def sample():
    return {'worldGeometry': {'vertices': [{'x':0,'y':0,'z':0},{'x':1,'y':0,'z':0},{'x':0,'y':0,'z':1}], 'triangles':[0,1,2]}}


def glb(document):
    data=json.dumps(document).encode(); data += b' '*(-len(data)%4)
    return struct.pack('<4sII',b'glTF',2,20+len(data))+struct.pack('<I4s',len(data),b'JSON')+data


class PortableTests(unittest.TestCase):
    def test_coordinate_roundtrip(self):
        for point in [[1,2,3],[-4,.2,-7],[0,0,0]]:
            x,y,z=a.godot_to_blender(point)
            self.assertEqual((x,z,-y),tuple(point))

    def test_face_orientation(self):
        _,faces=a.validated_surface(sample()); self.assertEqual(faces,[(0,2,1)])

    def test_reject_nonfinite(self):
        d=sample(); d['worldGeometry']['vertices'][0]['y']=float('nan')
        with self.assertRaises(ValueError): a.validated_surface(d)

    def test_reject_bad_index(self):
        for index in [3,-1,True,.5]:
            d=sample(); d['worldGeometry']['triangles'][0]=index
            with self.assertRaises(ValueError): a.validated_surface(d)

    def test_reject_short_triangle(self):
        d=sample(); d['worldGeometry']['triangles']=[0,1]
        with self.assertRaises(ValueError): a.validated_surface(d)

    def test_reject_degenerate(self):
        d=sample(); d['worldGeometry']['triangles']=[0,1,1]
        with self.assertRaises(ValueError): a.validated_surface(d)

    def test_output_scope(self):
        with tempfile.TemporaryDirectory() as td, mock.patch.object(a,'WORK',Path(td)/'work'):
            self.assertEqual(a.inside_work(Path(td)/'work'/'r'),Path(td)/'work'/'r')
            for p in [Path(td),Path(td)/'work',Path(td)/'work'/'..'/'native']:
                with self.assertRaises(ValueError): a.inside_work(p)

    def test_prepare_preserves_source_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); ws=root/'project'; stage=ws/a.STAGE; stage.parent.mkdir(parents=True)
            source=json.dumps(sample()).encode(); stage.write_bytes(source)
            ref=ws/a.REF; ref.parent.mkdir(parents=True); ref.write_bytes(b'unit-test-reference-only')
            with mock.patch.object(a,'WORK',root/'work'), mock.patch.object(a,'REF_SHA',a.digest(ref)):
                first=a.prepare(ws); second=a.prepare(ws)
                self.assertNotEqual(first,second)
                self.assertEqual(stage.read_bytes(),source)
                self.assertEqual(json.loads((first/'manifest.json').read_text())['triangles'],1)
                self.assertIn('f 1 3 2',(first/'context_terrain.obj').read_text())
                self.assertEqual((first/'reference.png').read_bytes(),ref.read_bytes())

    def test_reference_mismatch_stops_before_output(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); stage=root/a.STAGE; stage.parent.mkdir(parents=True); stage.write_text(json.dumps(sample()))
            ref=root/a.REF; ref.parent.mkdir(parents=True); ref.write_bytes(b'wrong')
            with mock.patch.object(a,'WORK',root/'work'):
                with self.assertRaises(ValueError): a.prepare(root)
                self.assertFalse((root/'work').exists())

    def test_glb_structural_summary(self):
        doc={'asset':{'version':'2.0'},'accessors':[{'count':3}],'meshes':[{'primitives':[{'attributes':{'POSITION':0}}]}]}
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'unit-test.glb'; p.write_bytes(glb(doc))
            self.assertEqual(a.inspect_glb(p)['triangles'],1)

    def test_glb_reject_external_image(self):
        d={'meshes':[{}],'images':[{'uri':'https://example.invalid/x.png'}]}
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'bad.glb'; p.write_bytes(glb(d))
            with self.assertRaises(ValueError): a.inspect_glb(p)

    def test_glb_reject_malformed(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'bad.glb'
            for data in [b'',b'garbage'*4,glb({'meshes':[]}),glb({'meshes':[{}]})[:-1]]:
                p.write_bytes(data)
                with self.assertRaises((ValueError,KeyError)): a.inspect_glb(p)

    def test_exclusive_evidence_write(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'result.json'; a.dump(p,{'old':1})
            with self.assertRaises(FileExistsError): a.dump(p,{'new':1})
            self.assertEqual(json.loads(p.read_text()),{'old':1})


if __name__=='__main__': unittest.main(verbosity=2)
